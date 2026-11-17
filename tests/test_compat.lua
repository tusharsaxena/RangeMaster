-- tests/test_compat.lua — core/Compat.lua: the client seam and the secret guards (clients-§3,
-- events-frames-taint-§8), routed from LibKa0s-Compat-1.0, and their library-absent stand-ins.
--
-- The library's own answers are tested in the LibKa0s repo. What is ours: that every wired member is
-- the library's on a full load, that the client answer follows the kit profile the suite runs under
-- (KA0S_KIT_CLIENT), and that the degraded load answers the documented absent values, the guards by
-- their one-rung bodies (LibKa0s docs/api/Compat/version-4-docs.md, "Degradation").

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local Loader = dofile("tests/_kit/loader.lua")
local profile = Loader.MockClient.current()

-- The members core/Compat.lua wires; the major carries more, which this addon does not reach yet.
local WIRED = { "IsForever", "IsRetail", "ClientKey", "ForClient", "IsSecret", "CanAccess", "IsSafeKey" }

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
  for _, name in ipairs({ "IsSecret", "CanAccess", "IsSafeKey" }) do
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
