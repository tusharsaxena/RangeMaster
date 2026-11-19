local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- The closed message bus (core/Bus.lua, architecture-§4). Producers publish on
-- NS.bus; each consumer subscribes on its own NS.NewBusTarget(). These tests run
-- against the harness's (message, target)-keyed AceEvent mock (tests/wow_mock.lua),
-- which fans a SendMessage out to every registered target exactly like the live lib.

test("a receiver on its own target hears a message, then is silent after unregister", function()
  local got = 0
  local target = NS.NewBusTarget()
  target:RegisterMessage("RM_TEST_Ping", function() got = got + 1 end)

  NS.bus:SendMessage("RM_TEST_Ping")
  assertEqual(got, 1, "receiver heard the message")

  target:UnregisterMessage("RM_TEST_Ping")
  NS.bus:SendMessage("RM_TEST_Ping")
  assertEqual(got, 1, "unregistered receiver goes silent")
end)

-- anti-pattern #33: two receivers of ONE message, each on its OWN target, must BOTH
-- fire. A no-op or single-slot mock (or two receivers sharing one target) would let
-- the second registration silently clobber the first — the exact bug the rule guards.
test("two receivers of one message both fire (no (message,target) clobber)", function()
  local a, b = 0, 0
  local ta, tb = NS.NewBusTarget(), NS.NewBusTarget()
  ta:RegisterMessage("RM_TEST_Fanout", function() a = a + 1 end)
  tb:RegisterMessage("RM_TEST_Fanout", function() b = b + 1 end)

  NS.bus:SendMessage("RM_TEST_Fanout")
  assertEqual(a, 1, "first receiver fired")
  assertEqual(b, 1, "second receiver fired (not clobbered by the first)")

  ta:UnregisterMessage("RM_TEST_Fanout")
  tb:UnregisterMessage("RM_TEST_Fanout")
end)

test("a message payload reaches the receiver after the message name", function()
  local seen
  local target = NS.NewBusTarget()
  -- CallbackHandler fires a function-ref callback as fn(message, ...payload).
  target:RegisterMessage("RM_TEST_Payload", function(_, value) seen = value end)
  NS.bus:SendMessage("RM_TEST_Payload", "hello")
  assertEqual(seen, "hello", "payload arrives after the message name")
  target:UnregisterMessage("RM_TEST_Payload")
end)

test("sending a message with no subscribers is a harmless no-op", function()
  local ok = pcall(function() NS.bus:SendMessage("RM_TEST_Nobody_Listening") end)
  assertTrue(ok, "SendMessage with no registrant does not error")
  assertFalse(false, "sanity")
end)

-- ── LibKa0s-Bus-1.0 (adopted at the LibKa0s v1.55.0 re-vendor) ────────────────────────────────

test("the bus record is LibKa0s-Bus-1.0's, built under the folder name", function()
  -- The live build must be on the library, not on the stub: a stub that answered here would keep
  -- every case above green while a disable left the subscriptions live.
  local lib = T.mocks.LibStub("LibKa0s-Bus-1.0", true)
  assertTrue(lib ~= nil, "the vendored Bus major registered in this build")
  assertTrue(NS.__busLib == lib, "core/Bus.lua resolved the library, not its stub")
  assertEqual(NS.busRecord.name, "RangeMaster", "the record carries the folder name")
end)

test("the catalog is strict: an undeclared key raises at the call site", function()
  -- Catalog's point for a PUBLISHER: `NS.bus:SendMessage(NS.MSG.REPIANT)` used to hand
  -- CallbackHandler a nil, which it drops without a word. Now the read itself raises.
  local err = T.assertError(function() return NS.MSG.REPIANT end,
    "reading an undeclared message key must raise")
  assertTrue(err:find("REPIANT", 1, true) ~= nil, "and the error names the key: " .. err)
  T.assertError(function() NS.MSG.NEW_ONE = "Ka0s_RangeMaster_NewOne" end,
    "adding a key after load must raise too")
end)

test("the catalog is exactly the five declared messages, each one prefixed for this addon", function()
  -- red under: a message added, renamed or dropped without this list moving with it.
  local want = {
    ANCHORS_CHANGED    = "Ka0s_RangeMaster_AnchorsChanged",
    BANDSETS_CHANGED   = "Ka0s_RangeMaster_BandSetsChanged",
    CONTAINERS_CHANGED = "Ka0s_RangeMaster_ContainersChanged",
    MODE_CHANGED       = "Ka0s_RangeMaster_ModeChanged",
    RANGE_UPDATED      = "Ka0s_RangeMaster_RangeUpdated",
  }
  local n = 0
  for key, name in pairs(want) do
    n = n + 1
    T.assertEqual(NS.MSG[key], name, key)
  end
  local seen = 0
  for _ in pairs(NS.MSG) do seen = seen + 1 end
  T.assertEqual(seen, n, "the catalog holds no undeclared message")
end)

test("with LibKa0s absent, receivers still get a private working target", function()
  local NS2 = dofile("tests/degraded_env.lua")()
  local heard = 0
  local target = NS2.NewBusTarget()
  T.assertTrue(type(target) == "table" and target ~= NS2.bus, "a private target, not the shared bus")
  target:RegisterMessage(NS2.MSG.MODE_CHANGED, function() heard = heard + 1 end)
  NS2.bus:SendMessage(NS2.MSG.MODE_CHANGED, "test", true)
  T.assertEqual(heard, 1, "the degraded target hears the message")
  T.assertEqual(NS2.BusStandDown(), 0, "and the untracked stub records nothing")
end)
