-- tests/test_bandset_choice.lua — the band set a container uses is the character's own
-- (modules/BandSetChoice.lua; spec docs/superpowers/specs/2026-11-26-band-set-per-character-design.md).
--
-- Every case runs on a FRESH ACCOUNT: the db is swapped for one shaped as real AceDB-3.0 is, with
-- every profile under sv.profiles, every character's store under sv.char[<charKey>] and the
-- current character's as db.char (the kit's AceDB fake has no character scope, spec C8). `login`
-- switches the character the way a relog does: the class, db.char and the load pass. The real db,
-- the class and UnitIsFriend are put back whether or not the case raised.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local B = NS.BandSets

--- The id of the first set whose origin is `key`, or nil.
local function setFrom(key)
  for _, id in ipairs(B.List()) do
    if B.Get(id).origin == key then return id end
  end
end

--- A container stored straight into the active profile (no renderer apply), answering its id.
local function addContainer(p, bandSet)
  local id = p.nextContainerId or 1
  p.nextContainerId = id + 1
  p.containers[id] = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
  p.containers[id].bandSet = bandSet or B.DefaultId()
  p.containerOrder[#p.containerOrder + 1] = id
  return id
end

--- Run `body(acct)` on a fresh account. `acct.login(charKey, classToken)` makes that character the
--- current one and runs the load pass; `acct.sv` is the raw SavedVariables table.
local function withAccount(body, svOverride)
  local savedDb, savedClass, savedFriend = NS.db, M.__context.classToken, M.UnitIsFriend
  local sv = svOverride or { profiles = { Default = {} }, char = {}, global = { schemaVersion = NS.SCHEMA_VERSION } }
  sv.char = sv.char or {}
  local db = { sv = sv, profiles = sv.profiles, global = sv.global, keys = { profile = "Default" } }
  db.profile = sv.profiles.Default
  function db.GetCurrentProfile() return db.keys.profile end
  local acct = { sv = sv, db = db }
  function acct.login(charKey, classToken)
    M.__context.classToken = classToken
    sv.char[charKey] = sv.char[charKey] or {}
    db.char, db.keys.char = sv.char[charKey], charKey
    NS.db = db
    NS:RunMigrations()
    return db.profile
  end
  local ok, err = pcall(body, acct)
  NS.db = savedDb
  M.__context.classToken = savedClass
  M.UnitIsFriend = savedFriend
  if NS.BandSetChoice and NS.BandSetChoice.Invalidate then NS.BandSetChoice.Invalidate() end
  NS.CM.__reset()
  if not ok then error(err, 0) end
end

--- The row the Containers page draws for `path`.
local function row(path)
  for _, r in ipairs(NS.Schema) do
    if r.path == path then return r end
  end
  error("no row " .. path)
end

test("bandset choice: two characters sharing one profile keep separate selections", function()
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    local cid = addContainer(p)
    NS.SelectContainer(cid)
    local caster = setFrom("caster40")
    local hunterSet = setFrom("hunter")
    -- The paladin picks Caster 40 through the row, as the dropdown writes it.
    row("container.bandSet").set(caster)
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), caster, "the paladin reads its pick")
    assertEqual(row("container.bandSet").get(), caster, "and the row shows it")
    -- The hunter, same profile, picks the Hunter set.
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), hunterSet, "the hunter never sees the paladin's pick")
    row("container.bandSet").set(hunterSet)
    -- Back on the paladin: still Caster 40.
    acct.login("Pal - Realm", "PALADIN")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), caster, "the paladin keeps its own pick")
    assertEqual(acct.sv.char["Hunt - Realm"].bandSetChoice.Default[cid].hostile, hunterSet,
      "each pick is stored in its character's scope, under the profile's name")
    NS.SelectContainer(nil)
  end)
end)

test("bandset choice: a new character with no pick gets its own class preset", function()
  withAccount(function(acct)
    -- The paladin made the profile, so the seed put the Paladin set first (the old '(default)').
    local p = acct.login("Pal - Realm", "PALADIN")
    local cid = addContainer(p)
    assertEqual(B.DefaultId(), setFrom("paladin"), "the seed's first set is the paladin's class set")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom("paladin"))
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom("hunter"),
      "red before: the hunter read the profile's Paladin set")
    assertEqual(NS.BandSetChoice.CharacterDefaultId(), setFrom("hunter"), "'(default)' is the hunter's own")
    assertEqual(row("container.bandSet").get(), 0, "with no pick the row reads Default band set")
    -- A class with no set in the profile falls back to the container's own field.
    acct.login("Rogue - Realm", "ROGUE")
    assertNil(setFrom("rogue"), "no Rogue set was seeded in this profile")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), p.containers[cid].bandSet,
      "no class set: the profile's field")
  end)
end)

test("bandset choice: a deleted set falls back, on every character, and a named target moves the pick", function()
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    local cid = addContainer(p)
    local a, b = B.Create("A", "healer"), B.Create("Bee", "caster40")
    NS.BandSetChoice.Set(cid, "bandSet", a)
    acct.login("Hunt - Realm", "HUNTER")
    NS.BandSetChoice.Set(cid, "bandSet", a)
    NS.BandSetChoice.Set(cid, "bandSetFriendly", a)
    assertTrue(B.Delete(a))
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom("hunter"), "the hunter falls back to its class set")
    assertNil(acct.sv.char["Hunt - Realm"].bandSetChoice.Default[cid], "the hunter's dead pick is cleared")
    assertNil(acct.sv.char["Pal - Realm"].bandSetChoice.Default[cid], "and the paladin's, through sv.char")
    acct.login("Pal - Realm", "PALADIN")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom("paladin"), "the paladin falls back to its own")
    -- A delete that names where its containers go moves the pick there.
    local c2 = B.Create("C", "healer")
    NS.BandSetChoice.Set(cid, "bandSet", c2)
    assertTrue(B.Delete(c2, b))
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), b, "the pick follows the named set")
    -- A stale id a hand edit left is pruned on load and reads the fallback.
    acct.sv.char["Pal - Realm"].bandSetChoice.Default[cid] = { hostile = 424242 }
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom("paladin"), "a stale id reads the fallback")
    acct.login("Pal - Realm", "PALADIN")
    assertNil(acct.sv.char["Pal - Realm"].bandSetChoice.Default[cid], "and the load pass prunes it")
  end)
end)

test("bandset choice: friendly nil follows hostile; false is Same as Band set; an id is the override", function()
  withAccount(function(acct)
    local p = acct.login("Hunt - Realm", "HUNTER")
    local cid = addContainer(p)
    local c = p.containers[cid]
    local isFriend = true
    M.UnitIsFriend = function() return isFriend end
    local caster, healer = setFrom("caster40"), setFrom("healer")
    NS.BandSetChoice.Set(cid, "bandSet", caster)
    assertEqual(B.ForUnit(c, "target", cid), caster, "no friendly anywhere: a friend reads the hostile set")
    -- The profile's override (a container preset's Healer) applies while the character has not chosen.
    c.bandSetFriendly = healer
    assertEqual(B.ForUnit(c, "target", cid), healer, "the profile's friendly override")
    NS.SelectContainer(cid)
    assertEqual(row("container.bandSetFriendly").get(), healer, "the row shows it")
    row("container.bandSetFriendly").set(0)
    assertEqual(B.ForUnit(c, "target", cid), caster, "Same as Band set: the character's own hostile set")
    assertEqual(row("container.bandSetFriendly").get(), 0)
    row("container.bandSetFriendly").set(setFrom("hunter"))
    assertEqual(B.ForUnit(c, "target", cid), setFrom("hunter"), "a chosen override")
    isFriend = false
    assertEqual(B.ForUnit(c, "target", cid), caster, "a hostile unit ignores the override")
    NS.SelectContainer(nil)
  end)
end)

test("bandset choice: the v5 step keeps the migrating character's pick, but never another class's set", function()
  -- A v4 account: the paladin picked Caster 40 on container 1 and the Paladin set on container 2 of a
  -- profile the paladin seeded; a second profile "Raid" has a container on the Healer set.
  local seed = {}
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    local c1, c2 = addContainer(p, setFrom("caster40")), addContainer(p, setFrom("paladin"))
    seed.c1, seed.c2, seed.caster, seed.paladin = c1, c2, setFrom("caster40"), setFrom("paladin")
    seed.profile = NS.Database.DeepCopy(p)
    seed.healer = setFrom("healer")
  end)
  local raid = NS.Database.DeepCopy(seed.profile)
  raid.containers[seed.c1].bandSet = seed.healer
  local function v4()
    return { profiles = { Default = NS.Database.DeepCopy(seed.profile), Raid = NS.Database.DeepCopy(raid) },
             char = {}, global = { schemaVersion = 4 } }
  end
  -- The paladin loads first.
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    assertEqual(acct.sv.global.schemaVersion, 5, "stamped at v5")
    local mine = acct.sv.char["Pal - Realm"].bandSetChoice
    assertEqual(mine.Default[seed.c1].hostile, seed.caster, "the paladin keeps Caster 40")
    assertEqual(mine.Default[seed.c2].hostile, seed.paladin, "and its own class set")
    assertEqual(mine.Raid[seed.c1].hostile, seed.healer, "a profile not in use is migrated too")
    assertEqual(B.ForUnit(p.containers[seed.c2], "target", seed.c2), seed.paladin)
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(B.ForUnit(p.containers[seed.c2], "target", seed.c2), setFrom("hunter"),
      "a hunter logging in later gets the Hunter set")
    assertEqual(B.ForUnit(p.containers[seed.c1], "target", seed.c1), setFrom("hunter"),
      "and its class set over the profile's Caster 40 (spec C9)")
  end, v4())
  -- The hunter loads first: the Paladin set is another class's, so it is not pinned.
  withAccount(function(acct)
    local p = acct.login("Hunt - Realm", "HUNTER")
    local mine = acct.sv.char["Hunt - Realm"].bandSetChoice
    assertNil(mine.Default[seed.c2], "another class's set is never pinned")
    assertEqual(mine.Default[seed.c1].hostile, seed.caster, "a generic set is")
    assertEqual(B.ForUnit(p.containers[seed.c2], "target", seed.c2), setFrom("hunter"), "so the hunter reads Hunter")
    acct.login("Pal - Realm", "PALADIN")
    assertEqual(B.ForUnit(p.containers[seed.c2], "target", seed.c2), seed.paladin, "and the paladin, Paladin")
  end, v4())
end)

test("bandset choice: profile copy carries the picks, reset forgets them, a container copy copies them", function()
  withAccount(function(acct)
    local p = acct.login("Hunt - Realm", "HUNTER")
    local cid = addContainer(p)
    local caster = setFrom("caster40")
    NS.BandSetChoice.Set(cid, "bandSet", caster)
    -- A container copy and a duplicate take the source's pick.
    local other = addContainer(p)
    assertTrue(NS.CM.CopySettings(cid, other, { "bandSet" }))
    assertEqual(B.ForUnit(p.containers[other], "target", other), caster, "Copy settings copies the pick")
    local dup = NS.CM.Duplicate(cid)
    assertEqual(B.ForUnit(p.containers[dup], "target", dup), caster, "Duplicate copies the pick")
    -- A profile copy into "Raid" carries this character's picks there.
    acct.sv.profiles.Raid = {}
    NS.BandSetChoice.CopyProfile("Default", "Raid")
    assertEqual(acct.sv.char["Hunt - Realm"].bandSetChoice.Raid[cid].hostile, caster)
    NS.BandSetChoice.ForgetProfile("Raid")
    assertNil(acct.sv.char["Hunt - Realm"].bandSetChoice.Raid, "a reset or delete forgets them")
  end)
end)

test("bandset choice: with no character store the profile fields are read and written as before (spec C8)", function()
  -- The suite's own db (the kit's AceDB fake) has no db.char.
  assertFalse(NS.BandSetChoice.HasStore(), "the kit's db has no character scope")
  local c = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
  c.bandSet = B.List()[#B.List()]
  assertEqual(B.ForUnit(c, "target", 1), c.bandSet, "the profile field is the selection")
  assertFalse(NS.BandSetChoice.Set(1, "bandSet", c.bandSet), "and there is nothing to write")
end)
