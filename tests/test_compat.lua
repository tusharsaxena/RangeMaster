-- tests/test_compat.lua — core/Compat.lua: the client seam and the secret guards (clients-§3,
-- events-frames-taint-§8), routed from LibKa0s-Compat-1.0, and their library-absent stand-ins.
--
-- The library's own answers are tested in the LibKa0s repo. What is ours: that every wired member is
-- the library's on a full load, that the client answer follows the kit profile the suite runs under
-- (KA0S_KIT_CLIENT), and that the degraded load answers the documented absent values, the guards by
-- their one-rung bodies (LibKa0s docs/api/Compat/version-4-docs.md, "Degradation").

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local Loader = dofile("tests/_kit/loader.lua")
local profile = Loader.MockClient.current()

-- The members core/Compat.lua wires; the major carries more, which this addon does not reach yet.
local WIRED = { "IsForever", "IsRetail", "ClientKey", "ForClient", "IsSecret", "CanAccess", "IsSafeKey",
  "GetSpellInfo" }

test("compat: the client answer follows the kit profile this run uses", function()
  -- red under: a Compat that hard-codes Retail on a full load.
  assertEqual(NS.Compat.ClientKey(), profile, "ClientKey under KA0S_KIT_CLIENT=" .. profile)
  assertEqual(NS.Compat.IsForever(), profile == "forever")
  assertEqual(NS.Compat.IsRetail(), profile == "retail")
end)

test("compat: ForClient serves nil and both everywhere, this client's token, and raises on a typo", function()
  assertTrue(NS.Compat.ForClient(nil), "nil serves both clients")
  assertTrue(NS.Compat.ForClient("both"), "\"both\" serves both clients")
  assertTrue(NS.Compat.ForClient({ profile }), "this client's own token")
  local other = profile == "retail" and "forever" or "retail"
  assertFalse(NS.Compat.ForClient({ other }), "the other client's token")
  T.assertError(function() NS.Compat.ForClient({ "retial" }) end)
end)

test("compat: every wired member is the library's on a full load", function()
  local lib = M.LibStub("LibKa0s-Compat-1.0", true)
  assertTrue(lib ~= nil, "the major loaded")
  for _, name in ipairs({ "IsSecret", "CanAccess", "IsSafeKey", "GetSpellInfo" }) do
    assertTrue(NS.Compat[name] == lib[name], name .. " is handed over by reference")
  end
  for _, name in ipairs(WIRED) do
    assertEqual(type(NS.Compat[name]), "function", name)
  end
end)

test("compat: the guards follow the client's issecretvalue", function()
  local restore = T.installSecretValue and T.installSecretValue() or nil
  local secret = T.secret and T.secret(5) or nil
  if secret ~= nil then
    assertTrue(NS.Compat.IsSecret(secret), "a secret is secret")
    assertFalse(NS.Compat.IsSafeKey(secret), "and is never a table key")
  end
  assertFalse(NS.Compat.IsSecret(300), "a plain number is not")
  assertTrue(NS.Compat.IsSafeKey(300), "and is a key")
  assertFalse(NS.Compat.IsSafeKey(nil), "nil is never a key")
  if restore then restore() end
end)

test("compat: the degraded load answers Retail and keeps the guards' one-rung bodies", function()
  local NS2, M2 = dofile("tests/degraded_env.lua")()
  assertEqual(NS2.Compat.ClientKey(), "retail", "the stand-in answers Retail")
  assertTrue(NS2.Compat.IsRetail(), "IsRetail")
  assertFalse(NS2.Compat.IsForever(), "IsForever")
  assertTrue(NS2.Compat.ForClient({ "retail" }), "a Retail declaration is served")
  assertFalse(NS2.Compat.ForClient({ "forever" }), "a Forever one is not")
  T.assertError(function() NS2.Compat.ForClient({ "retial" }) end)
  -- The guard, without the library, still reads the client's own test.
  M2.issecretvalue = function(v) return v == "S" end
  assertTrue(NS2.Compat.IsSecret("S"), "the stand-in asks issecretvalue")
  assertFalse(NS2.Compat.IsSafeKey("S"), "and refuses a secret key")
  assertTrue(NS2.Compat.IsSafeKey(1), "a plain key passes")
  M2.issecretvalue = nil
  assertFalse(NS2.Compat.IsSecret("S"), "with no secrets system nothing is secret")
end)

test("compat: no file outside the library reads a WOW_PROJECT global or an interface number", function()
  -- clients-§3: detection goes through LibKa0s-Compat-1.0 and only there.
  for _, path in ipairs(T.loadedAddonFiles) do
    local f = assert(io.open(path, "r"))
    local src = f:read("*a"):gsub("%-%-[^\n]*", "")
    f:close()
    assertFalse(src:find("WOW_PROJECT_", 1, true) ~= nil, path .. " reads a WOW_PROJECT global")
    assertFalse(src:find("GetBuildInfo", 1, true) ~= nil, path .. " reads the build info")
  end
end)

-- ---------------------------------------------------------------------------
-- The anchor reads (dynamic-bands plan D1): AnchorInRange and CurrentSpellID
-- ---------------------------------------------------------------------------

--- Run `body` with the spell client answering from `spec`: `known[id]`, `usable[id]` (default
--- usable), `inRange(id, unit)`, `info[idOrName] = { name, spellID }` and `override[id]`. Every
--- API is put back afterwards, raise or not.
local function withSpellClient(spec, body)
  local book, spell = M.C_SpellBook, M.C_Spell
  local real = { book.IsSpellKnown, spell.IsSpellUsable, spell.IsSpellInRange, spell.GetSpellInfo,
    spell.GetOverrideSpell }
  local known, usable, info, override = spec.known or {}, spec.usable or {}, spec.info or {}, spec.override or {}
  book.IsSpellKnown = function(id) return known[id] == true end
  spell.IsSpellUsable = function(id)
    if usable[id] == nil then return true, false end
    return usable[id], false
  end
  spell.IsSpellInRange = function(id, unit) return (spec.inRange or function() return nil end)(id, unit) end
  spell.GetSpellInfo = function(id)
    local r = info[id]
    if r then return { name = r[1], iconID = 1, castTime = 0, minRange = 0, maxRange = 40, spellID = r[2] } end
  end
  spell.GetOverrideSpell = function(id) return override[id] or id end
  local ok, err = pcall(body)
  book.IsSpellKnown, spell.IsSpellUsable, spell.IsSpellInRange, spell.GetSpellInfo, spell.GetOverrideSpell =
    real[1], real[2], real[3], real[4], real[5]
  if not ok then error(err, 0) end
end

test("compat: AnchorInRange answers the client's true and false for a known, usable spell", function()
  -- red under: a missing AnchorInRange, or one that drops the client's false.
  withSpellClient({ known = { [75] = true }, inRange = function(_, unit) return unit == "target" end }, function()
    assertTrue(NS.Compat.AnchorInRange(75, "target") == true, "in range")
    assertTrue(NS.Compat.AnchorInRange(75, "focus") == false, "out of range is a plain false")
  end)
end)

test("compat: AnchorInRange answers nil for an unknown, unusable, non-number or unanswered spell", function()
  -- red under: an AnchorInRange that skips the known or the usable gate (an unusable spell can report
  -- "in range" from anywhere, docs/midnight-quirks.md).
  withSpellClient({ known = { [75] = true, [76] = true }, usable = { [76] = false },
    inRange = function(id) if id == 77 then return nil end return true end }, function()
    assertNil(NS.Compat.AnchorInRange(99, "target"), "an unknown spell")
    assertNil(NS.Compat.AnchorInRange(76, "target"), "a known but unusable spell")
    assertNil(NS.Compat.AnchorInRange("Auto Shot", "target"), "a name is not an anchor id")
    assertNil(NS.Compat.AnchorInRange(nil, "target"), "no id")
  end)
  withSpellClient({ known = { [77] = true }, inRange = function() return nil end }, function()
    assertNil(NS.Compat.AnchorInRange(77, "target"), "the client's own nil stays nil")
  end)
end)

test("compat: AnchorInRange answers nil, never false, on a secret or a raise", function()
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    withSpellClient({ known = { [75] = true }, inRange = function() return T.secret(false) end }, function()
      assertNil(NS.Compat.AnchorInRange(75, "target"), "a secret answer is no answer")
    end)
    withSpellClient({ known = { [75] = true }, inRange = function() error("refused") end }, function()
      assertNil(NS.Compat.AnchorInRange(75, "target"), "a raise is no answer")
    end)
  end)
  restore()
  if not ok then error(err, 0) end
end)

test("compat: CurrentSpellID resolves a rank-1 ID to the learned rank by name", function()
  -- red under: a CurrentSpellID that returns the stored rank-1 ID (critic 10: LRC asks by name).
  withSpellClient({ known = { [14281] = true },
    info = { [3044] = { "Arcane Shot", 3044 }, ["Arcane Shot"] = { "Arcane Shot", 14281 } } }, function()
    assertEqual(NS.Compat.CurrentSpellID(3044), 14281, "the current rank")
  end)
end)

test("compat: CurrentSpellID keeps the ID when the name lookup has nothing, and nil for an unknown spell", function()
  withSpellClient({ info = { [75] = { "Auto Shot", 75 } } }, function()
    assertEqual(NS.Compat.CurrentSpellID(75), 75, "no spellbook answer: the ID itself")
    assertNil(NS.Compat.CurrentSpellID(424242), "the client has no such spell")
    assertNil(NS.Compat.CurrentSpellID("Auto Shot"), "a name is not an ID")
  end)
end)

test("compat: CurrentSpellID follows a known override and ignores an unknown or secret one", function()
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    local info = { [185358] = { "Arcane Shot", 185358 }, ["Arcane Shot"] = { "Arcane Shot", 185358 } }
    withSpellClient({ known = { [185358] = true, [999] = true }, info = info, override = { [185358] = 999 } }, function()
      assertEqual(NS.Compat.CurrentSpellID(185358), 999, "a known override replaces the ID")
    end)
    withSpellClient({ known = { [185358] = true }, info = info, override = { [185358] = 999 } }, function()
      assertEqual(NS.Compat.CurrentSpellID(185358), 185358, "an override the book does not know is not used")
    end)
    withSpellClient({ known = { [185358] = true }, info = info, override = { [185358] = T.secret(999) } }, function()
      assertEqual(NS.Compat.CurrentSpellID(185358), 185358, "a secret override is not used")
    end)
  end)
  restore()
  if not ok then error(err, 0) end
end)

test("compat: the degraded load's anchor reads answer nil", function()
  local NS2 = dofile("tests/degraded_env.lua")()
  assertNil(NS2.Compat.CurrentSpellID(75), "no spell-info reader: nothing to resolve")
  assertNil(NS2.Compat.AnchorInRange(75, "target"), "nothing known: no answer")
end)
