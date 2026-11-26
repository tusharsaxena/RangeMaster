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

--- The first set from preset `key`, made from the preset when the profile has none (as New from a
--- preset does): a new profile holds its creator's set alone (R4-RM-02).
local function own(key)
  return setFrom(key) or B.Create(nil, key)
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
  -- A profile event shows the first-run preset picker, previewing into this account's profile: it
  -- goes down with the preview dropped, so no later case restores it into its own profile.
  if NS.HidePresetPicker then NS.HidePresetPicker(true) end
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
    local caster = own("caster40")
    local hunterSet = own("hunter")
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
    -- A class with no set in the profile never lands on another class's set: its first load makes
    -- and assigns its own class set (R4-RM-01; BSC-REV read the first set that is no class's).
    assertNil(setFrom("rogue"), "no Rogue set was seeded in this profile")
    acct.login("Rogue - Realm", "ROGUE")
    assertTrue(setFrom("rogue") ~= nil, "the rogue's first load made the Rogue set")
    assertEqual(p.containers[cid].bandSet, setFrom("paladin"), "the container's field is the paladin's set")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom("rogue"),
      "red before: the rogue read the profile's Paladin set")
    assertEqual(NS.BandSetChoice.CharacterDefaultId(), setFrom("rogue"),
      "and '(default)' is the same set, never 'Paladin (default)'")
    assertEqual(NS.BandSetChoice.FallbackId(p.containers[cid]), NS.BandSetChoice.CharacterDefaultId(),
      "the row's Default band set names the set '(default)' marks")
    -- The assignment outranks a container's profile field, even a generic one (R4-RM-01).
    local generic = addContainer(p, own("caster40"))
    assertEqual(B.ForUnit(p.containers[generic], "target", generic), setFrom("rogue"),
      "the character's assignment over the profile's Caster 40")
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
    local caster, healer = own("caster40"), own("healer")
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
    local c1, c2 = addContainer(p, own("caster40")), addContainer(p, setFrom("paladin"))
    seed.c1, seed.c2, seed.caster, seed.paladin = c1, c2, own("caster40"), setFrom("paladin")
    seed.healer = own("healer")
    seed.profile = NS.Database.DeepCopy(p)
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
    assertEqual(acct.sv.global.schemaVersion, NS.SCHEMA_VERSION, "stamped at the ladder's top")
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
    -- The known trade-off (spec addendum, BANDS-28): pre-v5 data has no owner, so a generic set is
    -- pinned on whoever loads first. The paladin's Caster 40 went to the hunter; the paladin, with no
    -- pick of its own, follows its class set (C9).
    assertNil(acct.sv.char["Pal - Realm"].bandSetChoice and acct.sv.char["Pal - Realm"].bandSetChoice.Default,
      "the step runs once per account, so the paladin has no pins")
    assertEqual(B.ForUnit(p.containers[seed.c1], "target", seed.c1), seed.paladin,
      "the paladin's c1 reads its class set, not the Caster 40 it had chosen")
  end, v4())
end)

test("bandset choice: profile copy carries the picks, reset forgets them, a container copy copies them", function()
  withAccount(function(acct)
    local p = acct.login("Hunt - Realm", "HUNTER")
    local cid = addContainer(p)
    local caster = own("caster40")
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

test("bandset choice: the AceDB profile events reach every character's picks", function()
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    local cid = addContainer(p)
    local caster, healer = own("caster40"), own("healer")
    NS.BandSetChoice.Set(cid, "bandSet", caster)
    acct.login("Hunt - Realm", "HUNTER")
    NS.BandSetChoice.Set(cid, "bandSet", healer)
    -- A copy, as AceDB does it: the source copied into the active profile, then OnProfileCopied.
    acct.sv.profiles.Raid = NS.Database.DeepCopy(acct.sv.profiles.Default)
    acct.db.keys.profile, acct.db.profile = "Raid", acct.sv.profiles.Raid
    NS.OnProfileCopied("Default")
    assertEqual(acct.sv.char["Pal - Realm"].bandSetChoice.Raid[cid].hostile, caster, "the paladin's picks are copied")
    assertEqual(B.ForUnit(acct.db.profile.containers[cid], "target", cid), healer, "and the hunter's apply on Raid")
    -- A reset, as AceDB does it: the profile emptied in place, then OnProfileReset.
    for k in pairs(acct.db.profile) do acct.db.profile[k] = nil end
    NS.OnProfileReset()
    assertNil(acct.sv.char["Pal - Realm"].bandSetChoice.Raid, "a reset forgets every character's picks")
    assertNil(acct.sv.char["Hunt - Realm"].bandSetChoice.Raid)
    -- A delete of the profile not in use.
    NS.OnProfileDeleted("Default")
    assertNil(acct.sv.char["Pal - Realm"].bandSetChoice.Default, "a delete forgets that profile's picks")
    assertNil(acct.sv.char["Hunt - Realm"].bandSetChoice.Default)
  end)
end)

test("bandset choice: the load pass drops a pick on a deleted container", function()
  withAccount(function(acct)
    local p = acct.login("Hunt - Realm", "HUNTER")
    local keep, gone = addContainer(p), addContainer(p)
    NS.BandSetChoice.Set(keep, "bandSet", own("caster40"))
    NS.BandSetChoice.Set(gone, "bandSet", own("caster40"))
    assertTrue(NS.CM.Delete(gone))
    acct.login("Hunt - Realm", "HUNTER")
    local mine = acct.sv.char["Hunt - Realm"].bandSetChoice.Default
    assertNil(mine[gone], "the deleted container's pick is pruned")
    assertEqual(mine[keep].hostile, own("caster40"), "the live one's stays")
  end)
end)

test("bandset choice: a respec never moves the assignment (R4-RM-01)", function()
  local realSpec = NS.Compat.PlayerSpecID
  local spec = 577
  NS.Compat.PlayerSpecID = function() return spec end
  local ok, err = pcall(withAccount, function(acct)
    acct.login("Pal - Realm", "PALADIN")
    local p = acct.login("DH - Realm", "DEMONHUNTER")
    local cid = addContainer(p)
    local havoc = NS.BandSetPresets.DefaultFor("DEMONHUNTER", 577)
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom(havoc), "Havoc: its own class set, assigned")
    spec = 1480
    NS:OnSpellsChanged()
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom(havoc),
      "a respec to Devourer keeps the assignment")
    acct.login("DH - Realm", "DEMONHUNTER")
    assertEqual(B.ForUnit(p.containers[cid], "target", cid), setFrom(havoc), "and so does a /reload")
  end)
  NS.Compat.PlayerSpecID = realSpec
  assertTrue(ok, tostring(err))
end)

test("bandset choice: Copy settings without the band-set sections leaves the picks alone", function()
  withAccount(function(acct)
    local p = acct.login("Hunt - Realm", "HUNTER")
    local from, to = addContainer(p), addContainer(p)
    NS.BandSetChoice.Set(from, "bandSet", own("caster40"))
    NS.BandSetChoice.Set(to, "bandSet", own("healer"))
    assertTrue(NS.CM.CopySettings(from, to, { "layout" }))
    assertEqual(B.ForUnit(p.containers[to], "target", to), own("healer"), "the target keeps its own pick")
  end)
end)

test("bandset choice: other characters' picks are counted for the Used by line", function()
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    local cid = addContainer(p)
    local a = B.Create("A", "healer")
    NS.BandSetChoice.Set(cid, "bandSet", a)
    assertEqual(NS.BandSetChoice.OthersUsing(a), 0, "this character's own pick is not an other's")
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(NS.BandSetChoice.OthersUsing(a), 1, "the paladin's pick, seen from the hunter")
    assertEqual(NS.BandSetChoice.OthersUsing(own("caster40")), 0)
  end)
end)

-- ---------------------------------------------------------------------------
-- R4-RM-01: the band set assigned to each character, per profile, written at its first load
-- (db.char.bandSetAssigned[<profile>] = setId; the owner, round 4: "the right class specific bandset
-- should be assigned to that character"; "One per character", set from "Use for this character")
-- ---------------------------------------------------------------------------

--- The set `charKey` is assigned on profile `name` (default "Default"), read from the raw store.
local function assignedOf(acct, charKey, name)
  local store = acct.sv.char[charKey]
  local t = store and store.bandSetAssigned
  return t and t[name or "Default"]
end

test("bandset assignment: written at a character's first load on a profile, and shown as its default", function()
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    assertEqual(assignedOf(acct, "Pal - Realm"), setFrom("paladin"), "the paladin is assigned its class set")
    acct.login("Hunt - Realm", "HUNTER")
    local hunter = setFrom("hunter")
    assertEqual(assignedOf(acct, "Hunt - Realm"), hunter, "red before: no assignment was written anywhere")
    assertEqual(NS.BandSetChoice.Assigned(), hunter, "Assigned() reads it")
    -- The Band sets page opens on it (the owner's screenshot 137: it opened on Paladin).
    NS.SelectBandSet(nil)
    assertEqual(select(2, NS.SelectedBandSet()), hunter, "red before: the page opened on the profile's first set")
    local list = NS.__bandSetPickerEntries()
    assertTrue(list[hunter]:find("(default)", 1, true) ~= nil, "'(default)' names the assignment")
    assertNil(list[setFrom("paladin")]:find("(default)", 1, true), "and nothing else")
    -- The Containers row's "Default band set (X)" is the same set.
    local cid = addContainer(p)
    assertEqual(NS.BandSetChoice.FallbackId(p.containers[cid]), hunter)
  end)
end)

test("bandset assignment: a swap away and back, another profile and a /reload change nothing", function()
  withAccount(function(acct)
    acct.login("Pal - Realm", "PALADIN")
    acct.login("Hunt - Realm", "HUNTER")
    local hunter = assignedOf(acct, "Hunt - Realm")
    -- The hunter switches to "Raid" and back, as AceDB does it: OnProfileShutdown on the old profile
    -- (a first-run preset preview goes back into it), then OnProfileChanged on the new one.
    local function switch(name)
      NS.OnProfileShutdown()
      acct.sv.profiles[name] = acct.sv.profiles[name] or {}
      acct.db.keys.profile, acct.db.profile = name, acct.sv.profiles[name]
      NS.OnProfileChanged()
    end
    switch("Raid")
    assertTrue(assignedOf(acct, "Hunt - Realm", "Raid") ~= nil, "a first load on Raid assigns there too")
    switch("Default")
    assertEqual(assignedOf(acct, "Hunt - Realm"), hunter, "back on Default: the same set")
    acct.login("Pal - Realm", "PALADIN")
    acct.login("Hunt - Realm", "HUNTER")
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(assignedOf(acct, "Hunt - Realm"), hunter, "a swap of characters and a /reload: still the same")
    assertEqual(assignedOf(acct, "Pal - Realm"), setFrom("paladin"), "and the paladin keeps its own")
  end)
end)

test("bandset assignment: an edited or renamed copy of the class set is reused, never duplicated", function()
  withAccount(function(acct)
    acct.login("Pal - Realm", "PALADIN")
    local hunter = own("hunter")
    B.Rename(hunter, "My hunter bands")
    B.SetBand(hunter, 1, "label", "XX")
    local before = #B.List()
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(assignedOf(acct, "Hunt - Realm"), hunter, "the first set from the Hunter preset, by origin")
    assertEqual(#B.List(), before, "and nothing was created")
  end)
end)

test("bandset assignment: 'Use for this character' changes it; every container without a pick follows", function()
  withAccount(function(acct)
    local p = acct.login("Hunt - Realm", "HUNTER")
    local free, picked = addContainer(p), addContainer(p)
    local caster, healer = own("caster40"), own("healer")
    NS.BandSetChoice.Set(picked, "bandSet", healer)
    NS.SelectBandSet(caster)
    local line = NS.__bandSetOriginLine()
    local act = line and line.acts[#line.acts]
    assertEqual(act and act.text, "Use for this character", "the page offers the action on another set")
    assertFalse(act.disabled)
    act.onClick()
    assertEqual(assignedOf(acct, "Hunt - Realm"), caster, "the click assigns the set shown")
    assertEqual(B.ForUnit(p.containers[free], "target", free), caster, "a container with no pick follows it")
    assertEqual(B.ForUnit(p.containers[picked], "target", picked), healer, "a container's own pick outranks it")
    line = NS.__bandSetOriginLine()
    act = line.acts[#line.acts]
    assertEqual(act.text, "This character's band set", "on the assigned set the action says so")
    assertTrue(act.disabled, "and is disabled")
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(assignedOf(acct, "Hunt - Realm"), caster, "the pick persists over a /reload")
    assertFalse(NS.BandSetChoice.Assign(424242), "a set id that names no set is refused")
    assertEqual(assignedOf(acct, "Hunt - Realm"), caster)
    -- A set with no preset still offers the action, with a line of its own.
    local blank = B.Create("Blank", { { from = 0, label = "ANY" } })
    NS.SelectBandSet(blank)
    line = NS.__bandSetOriginLine()
    assertEqual(line and line.acts[1].text, "Use for this character")
    NS.SelectBandSet(nil)
  end)
end)

test("bandset assignment: deleting an assigned set moves the assignment, and never re-creates the preset", function()
  withAccount(function(acct)
    acct.login("Pal - Realm", "PALADIN")
    acct.login("Hunt - Realm", "HUNTER")
    local hunter = setFrom("hunter")
    acct.login("Pal - Realm", "PALADIN")
    -- Seen from the paladin, the hunter's assignment counts on the Used by line.
    assertEqual(NS.BandSetChoice.OthersUsing(hunter), 1, "red before: only picks were counted")
    local caster = own("caster40")
    assertTrue(B.Delete(hunter, caster))
    assertEqual(assignedOf(acct, "Hunt - Realm"), caster, "the named target takes the assignment")
    acct.login("Hunt - Realm", "HUNTER")
    assertNil(setFrom("hunter"), "the hunter's next load does not re-create the Hunter set")
    assertEqual(assignedOf(acct, "Hunt - Realm"), caster, "it keeps the set the delete moved it to")
    -- A delete that names nothing moves it to the set the containers move to (the first in order).
    assertTrue(B.Delete(caster))
    assertEqual(assignedOf(acct, "Hunt - Realm"), B.DefaultId(), "the default set takes it")
    -- A stale id a hand edit left is dropped on load, and the first-load rule runs again.
    acct.sv.char["Hunt - Realm"].bandSetAssigned.Default = 424242
    assertTrue(NS.BandSetChoice.Assigned() == nil, "a stale id is no assignment")
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(assignedOf(acct, "Hunt - Realm"), setFrom("hunter"), "the load pass assigns afresh")
  end)
end)

test("bandset assignment: a profile copy copies every character's, a reset or delete forgets them", function()
  withAccount(function(acct)
    acct.login("Pal - Realm", "PALADIN")
    acct.login("Hunt - Realm", "HUNTER")
    local caster = own("caster40")
    NS.BandSetChoice.Assign(caster)
    -- A copy, as AceDB does it: the source copied into the active profile, then OnProfileCopied.
    acct.sv.profiles.Raid = NS.Database.DeepCopy(acct.sv.profiles.Default)
    acct.db.keys.profile, acct.db.profile = "Raid", acct.sv.profiles.Raid
    NS.OnProfileCopied("Default")
    assertEqual(assignedOf(acct, "Hunt - Realm", "Raid"), caster, "the hunter's assignment is copied")
    assertEqual(assignedOf(acct, "Pal - Realm", "Raid"), setFrom("paladin"), "and the paladin's")
    -- A reset: every character's is forgotten, and only the resetting character is assigned again.
    for k in pairs(acct.db.profile) do acct.db.profile[k] = nil end
    NS.OnProfileReset()
    assertNil(assignedOf(acct, "Pal - Realm", "Raid"), "the paladin's is forgotten")
    assertEqual(assignedOf(acct, "Hunt - Realm", "Raid"), setFrom("hunter"), "the hunter's load pass assigns afresh")
    NS.OnProfileDeleted("Default")
    assertNil(assignedOf(acct, "Pal - Realm"), "a delete forgets that profile's")
    assertNil(assignedOf(acct, "Hunt - Realm"))
  end)
end)

test("bandset assignment: the Ka0s container preset reads it, never a set matched by name", function()
  withAccount(function(acct)
    acct.login("Hunt - Realm", "HUNTER")
    local hunter = setFrom("hunter")
    B.Rename(hunter, "Mine")
    local before = #B.List()
    assertEqual(NS.Presets.__classSet(), hunter, "red before: a renamed class set was created again")
    assertEqual(#B.List(), before)
    NS.BandSetChoice.Assign(own("caster40"))
    assertEqual(NS.Presets.__classSet(), own("caster40"), "a manual assignment is the preset's class set")
  end)
end)

test("bandset assignment: a Devourer whose spec is not readable yet is assigned at the first event that reads it", function()
  local realSpec = NS.Compat.PlayerSpecID
  local spec = nil
  NS.Compat.PlayerSpecID = function() return spec end
  local ok, err = pcall(withAccount, function(acct)
    acct.login("Pal - Realm", "PALADIN")
    if not NS.BandSetPresets.demonhunter then return end -- a client with no Demon Hunter
    acct.login("DH - Realm", "DEMONHUNTER")
    assertNil(assignedOf(acct, "DH - Realm"), "an unreadable spec defers the assignment")
    spec = 1480
    NS:OnEnterWorld("PLAYER_ENTERING_WORLD", true, false)
    assertEqual(assignedOf(acct, "DH - Realm"), own("caster40"), "Devourer: Caster 40, not Demon Hunter")
    spec = 577
    NS:OnSpellsChanged()
    assertEqual(assignedOf(acct, "DH - Realm"), own("caster40"), "and a respec never moves it")
  end)
  NS.Compat.PlayerSpecID = realSpec
  assertTrue(ok, tostring(err))
end)

test("bandset assignment: the schema is v6, and no character store means no assignment (spec C8)", function()
  assertEqual(NS.SCHEMA_VERSION, 6)
  assertNil(NS.BandSetChoice.Assigned(), "the kit's db has no character scope")
  assertFalse(NS.BandSetChoice.Assign(B.DefaultId()), "and nothing to write")
  withAccount(function(acct)
    acct.login("Pal - Realm", "PALADIN")
    assertEqual(acct.sv.global.schemaVersion, 6, "a v5 account is stamped v6")
    assertEqual(type(acct.sv.char["Pal - Realm"].bandSetAssigned), "table", "with the table")
  end, { profiles = { Default = {} }, char = {}, global = { schemaVersion = 5 } })
end)

-- ---------------------------------------------------------------------------
-- R4-RM-02: a new profile seeds only its creator's set; "Your band sets" grows as characters are
-- assigned or pick sets (the owner, round 4: "Only bandsets that have been assigned to a character
-- should show up in 'Your band sets'"; answered "New profiles only")
-- ---------------------------------------------------------------------------

--- The origins of the stored sets, in order, as one string.
local function origins()
  local out = {}
  for _, id in ipairs(B.List()) do out[#out + 1] = tostring(B.Get(id).origin) end
  return table.concat(out, ",")
end

test("bandset seeding: a new profile holds its creator's set alone, and grows as characters arrive", function()
  withAccount(function(acct)
    acct.login("Pal - Realm", "PALADIN")
    assertEqual(origins(), "paladin", "red before: the seed added Melee / Ranged, Caster 40, Healer and Hunter too")
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(origins(), "paladin,hunter", "the hunter's first load adds its own set")
    local list = NS.__bandSetPickerEntries()
    assertTrue(list[setFrom("hunter")]:find("(default)", 1, true) ~= nil, "and the hunter's picker marks it")
    -- The hunter makes Caster 40 its own through "Use this preset" (New, from the preset) and uses it.
    local caster = B.Create(nil, "caster40")
    assertTrue(NS.UseBandSetForCharacter(caster))
    assertEqual(origins(), "paladin,hunter,caster40", "a set the player made joins the list")
    acct.login("Pal - Realm", "PALADIN")
    acct.login("Hunt - Realm", "HUNTER")
    assertEqual(NS.BandSetChoice.Assigned(), caster, "the hunter's pick persists")
    acct.login("Rogue - Realm", "ROGUE")
    assertEqual(origins(), "paladin,hunter,caster40,rogue", "a rogue gets its own set, nothing else is added")
  end)
end)

test("bandset seeding: a container preset adds the sets it uses, and nothing else", function()
  withAccount(function(acct)
    acct.login("Pal - Realm", "PALADIN")
    NS.Presets.Apply("ka0s")
    assertEqual(origins(), "paladin,healer", "Ka0s adds the Healer set for friends")
  end)
end)

test("bandset seeding: an existing profile keeps every set it has (owner: new profiles only)", function()
  local five = {}
  for _, key in ipairs({ "paladin", "melee_ranged", "caster40", "healer", "hunter" }) do
    five[#five + 1] = key
  end
  withAccount(function(acct)
    local p = acct.login("Pal - Realm", "PALADIN")
    for i = 2, #five do B.Create(nil, five[i]) end
    acct.sv.global.schemaVersion = 5
    acct.login("Mage - Realm", "MAGE")
    assertEqual(origins(), table.concat(five, ",") .. ",mage", "nothing pruned; the mage's own set is added")
    assertEqual(#p.bandSetOrder, 6)
  end)
end)
