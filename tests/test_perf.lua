-- tests/test_perf.lua — this addon's side of the perf harness (performance).
--
-- The probe itself is LibKa0s-Perf and is tested in that repo: buckets, JSON, the record schema, the
-- report, the ring, the measurement windows and the panel all have suites there. Duplicating them
-- here would mean two places to fix one bug.
--
-- What is ours, and what this file covers: the descriptor is well-formed, every bucket we declare is
-- actually reached by a bracket, and Suspend genuinely makes THIS addon inert.

local T = _G.RM_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local P = NS.Perf

-- Drain any timer a resume armed, so no later suite inherits it.
local function settle()
  for i = #mocks.__timers, 1, -1 do mocks.__timers[i] = nil end
end

local function resume()
  P.Resume()
  settle()
end

local function reset()
  P.on = false
  P.run = false
  P.armed, P.recording = nil, nil
  -- `P.suspended` is the LATCH's answer since Perf 12 and raises on assignment, which is the point:
  -- there is one place the addon's inert state lives and a test cannot fork it. Release the hold
  -- instead, which is what the probe itself does.
  NS.lifecycle:Release("perf")
  P.label = nil
  P.Reset()
  settle()
  mocks.__profileMs = 0
  _G.RangeMasterPerfDB = nil
end

-- ── the descriptor ──────────────────────────────────────────────────────────────────────────

-- Identity search: is `needle` reachable anywhere under `root`? Cycle-safe, and keys count as much
-- as values — a ring parked as `db.profile[someTable]` would hide from a value-only walk.
local function reaches(root, needle, seen)
  if root == needle then return true end
  if type(root) ~= "table" then return false end
  seen = seen or {}
  if seen[root] then return false end
  seen[root] = true
  for k, v in pairs(root) do
    if reaches(k, needle, seen) or reaches(v, needle, seen) then return true end
  end
  return false
end

-- ── the brackets ────────────────────────────────────────────────────────────────────────────

-- ── suspend / resume ────────────────────────────────────────────────────────────────────────

-- ── output routing ──────────────────────────────────────────────────────────────────────────

-- ── the degraded install (no LibKa0s) ───────────────────────────────────────────────────────
--
-- LibKa0s is vendored, so it can go missing: a partial unzip, a user pruning libs/, a packager that
-- dropped the folder. core/PerfSetup.lua substitutes a stub for the probe in that case, and the stub
-- has to answer for every member the addon calls — including OnCommand, because `/rm perf` is
-- registered unconditionally in settings/Slash.lua.
--
-- Built as a SECOND, self-contained environment rather than by poking at the shared one: the whole
-- point is a load with the library absent, which cannot be simulated after the fact. Nothing here
-- calls InitDB or CreateOptionsPanel, so the shared suite's SavedVariables globals are untouched.
-- Built by tests/degraded_env.lua, which more than one suite now needs (tests/test_optionssetup.lua
-- drives the settings stub through the same load), so the environment is defined once.
local loadDegraded = dofile("tests/degraded_env.lua")

local function chatOf(mocks2, fn)
  local out = {}
  mocks2.DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) out[#out + 1] = msg end
  fn()
  return out
end

-- The degradation stub in core/DebugLogSetup.lua is a second implementation of the debug surface,
-- reached only when the vendored library is missing. Before the extraction there was one
-- implementation of `/rm debug` and the suite pinned it; there are two now, and this is what keeps
-- the second one honest. Driven by loading the addon without the library, never by hand-stubbing.

test("debug: the flag still flips and acks with LibKa0s absent", function()
  local NS2, mocks2 = loadDegraded()
  NS2.State.debug = false
  local out = chatOf(mocks2, function() NS2.Slash:OnSlash("debug on") end)
  assertTrue(NS2.State.debug == true, "the flag is ours, so it works with or without the library")
  assertTrue(#out > 0, "and the user is told")
  chatOf(mocks2, function() NS2.Slash:OnSlash("debug off") end)
  assertFalse(NS2.State.debug, "and off again")
end)

test("debug: /rm debug names the missing library instead of erroring", function()
  local NS2, mocks2 = loadDegraded()
  local out = chatOf(mocks2, function() NS2.Slash:OnSlash("debug") end)
  assertTrue(table.concat(out, "\n"):find("LibKa0s", 1, true) ~= nil,
    "the bare verb should say why there is no window: " .. table.concat(out, "\n"))
end)

test("debug: every member the addon reaches for answers with LibKa0s absent", function()
  -- settings/General.lua, settings/Slash.lua and core/PerfSetup.lua between them touch all of
  -- these. A member missing from the stub is a Lua error in exactly the install it exists for.
  local NS2 = loadDegraded()
  local D = NS2.DebugLog
  assertTrue(type(D) == "table", "NS.DebugLog exists")
  local spec = D:ConsoleCheckbox()
  assertEqual(type(spec.label), "string")
  assertEqual(type(spec.tooltip), "string")
  assertFalse(spec.get(), "there is no window to be shown")
  local ok, err = pcall(function()
    spec.set(true)
    D:Add("Perf", "a line")
    D:Show(); D:Hide(); D:Toggle()
    D:IsShown(); D:IsEnabled(); D:Clear(); D:ShowCopy(); D:RefreshHeader()
    D:BufferSize(); D:LastLine(); D:FindLine("x")
    D.MakeCloseButton(nil, function() end)
    NS2.Debug("Absorb", "value=%s", 1)
  end)
  assertTrue(ok, "nothing the addon calls may raise: " .. tostring(err))
end)

-- The degraded load asks the stand-down latch (NS.IsStoodDown), not the Perf stub's `suspended`
-- field, whose literal could never fail for a latch reason.
-- red under: a degraded NS.IsStoodDown that answers true (a latch stub left holding).
test("perf: the addon loads with LibKa0s absent", function()
  local NS2 = loadDegraded()
  assertEqual(NS2.Perf.on, false, "the bracket gate is off and stays off")
  assertEqual(NS2.IsStoodDown(), false, "and the stand-down latch reports a running addon")
  assertEqual(type(NS2.Perf.Note), "function", "Note")
end)

test("perf: /rm perf explains itself instead of erroring with LibKa0s absent", function()
  local NS2, mocks2 = loadDegraded()
  for _, line in ipairs({ "perf", "perf start", "perf finish", "perf report" }) do
    local out = chatOf(mocks2, function() NS2.Slash:OnSlash(line) end)
    assertTrue(#out > 0, "/rm " .. line .. " said nothing")
    assertTrue(table.concat(out, "\n"):find("LibKa0s", 1, true) ~= nil,
      "/rm " .. line .. " should name the missing library: " .. table.concat(out, "\n"))
  end
end)

-- -- the `L` trap -----------------------------------------------------------------------------

test("every perf step label the library renders is prose, not its own STRINGS key", function()
  -- core/PerfSetup.lua:35's descriptor omits `L`. P.STEPS is built once in lib:New by resolving
  -- each step's STRINGS key, and PerfPanel paints step.label straight onto the row button — so
  -- this is the rendered string, on the live instance, and it is the exact surface KickCD shipped
  -- reading STEP_START / STEP_MEASURE_A / PANEL_TITLE_SUFFIX verbatim.
  -- red under: giving the descriptor an `L` that answers STEP_* with the key.
  assertTrue(#(NS.Perf.STEPS or {}) > 0, "the perf instance must have built its step list")
  for _, step in ipairs(NS.Perf.STEPS) do
    assertTrue(type(step.label) == "string" and step.label ~= "",
      "step " .. tostring(step.key) .. " has no label")
    assertNil(step.label:match("^[A-Z][A-Z0-9_]+$"),
      "step '" .. tostring(step.key) .. "' resolved to prose, not to its own key: " .. step.label)
  end
end)

test("Perf: the descriptor hands the library the FOLDER name, not just the frame name", function()
  -- PerfPanel minor 4 draws the panel's close control from
  -- `core.MakeCloseButton(frame, P.HidePanel, d.addonName or d.name)`. This addon answers both
  -- fields with the same string, so `name` alone would reach the right texture BY LUCK -- which
  -- is the whole reason to pin the explicit field: the two are different questions, and a host
  -- where they diverge hands the library a path into nowhere that draws nothing and raises
  -- nothing. Testing the ARGUMENT, not the appearance.
  -- red under: dropping `addonName` and leaving the panel to infer it from `name`.
  local f = io.open("core/PerfSetup.lua", "r")
  assertTrue(f ~= nil, "cannot open core/PerfSetup.lua (tests run from the repo root)")
  local src = f:read("*a")
  f:close()
  local body = src:gsub("%-%-[^\r\n]*", "")
  assertTrue(body:match("addonName%s*=%s*addonName") ~= nil,
    "the perf descriptor does not pass addonName, so the panel's close falls back to `name`")
  assertNil(body:find("\"RangeMaster\"", 1, true),
    "the descriptor must name this addon through `addonName`, the first vararg, never as a literal")
end)

-- ── this addon's wiring ─────────────────────────────────────────────────────────────────────

test("perf: the addon holds a real LibKa0s-Perf instance, on this addon's latch", function()
  assertTrue(type(P.Note) == "function" and type(P.BuildRecord) == "function",
    "NS.Perf is the library instance, not the degradation stub")
  assertEqual(P.BUCKET_ORDER[1], "combatEdge", "the descriptor's one declared bucket")
  assertEqual(#P.BUCKET_ORDER, 1, "and nothing undeclared")
end)

test("perf: records identify this addon and land in its own global", function()
  reset()
  P.Save(P.BuildRecord("cap"))
  assertEqual(_G.RangeMasterPerfDB.runs[1].addon, "RangeMaster", "self-identifying")
  reset()
end)

test("perf: the ring is reachable through its own global and nowhere in AceDB", function()
  reset()
  P.Save(P.BuildRecord("cap"))
  local ring = _G.RangeMasterPerfDB
  local record = ring.runs[1]
  assertTrue(reaches(ring, record), "sanity: the walk can find a record it is pointed at")
  for _, where in ipairs({ "profile", "global" }) do
    local tree = NS.db and NS.db[where]
    assertFalse(reaches(tree, ring), "the ring is reachable from db." .. where)
    assertFalse(reaches(tree, record), "a saved run is reachable from db." .. where)
  end
  reset()
end)

test("perf: brackets record nothing while capture is off", function()
  reset()
  mocks.__profileMs = 1
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  assertNil(P.__buckets().combatEdge, "a dormant bracket recorded")
  reset()
end)

test("perf: every declared bucket is reached by a real bracket", function()
  -- A declared bucket no bracket reaches is a lie in every report the addon prints.
  reset()
  P.on = true
  mocks.__profileMs = 1
  NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  P.on = false
  local recorded = P.__buckets()
  for _, key in ipairs(P.BUCKET_ORDER) do
    assertTrue(recorded[key] ~= nil, "declared bucket '" .. key .. "' never fired")
  end
  reset()
end)

test("perf: suspend unregisters the lifecycle events, and resume restores them", function()
  reset()
  NS.addon:RegisterLifecycleEvents()
  P.Suspend()
  assertEqual(NS.addon.__events["PLAYER_REGEN_DISABLED"], nil, "combat event dropped")
  resume()
  assertTrue(NS.addon.__events["PLAYER_REGEN_DISABLED"] ~= nil, "restored on resume")
end)

test("perf: the suspended state is session-only, never persisted", function()
  reset()
  mocks.__resetSvWrites()
  P.Suspend()
  assertEqual(#mocks.__svWrites(), 0, "the suspend wrote SavedVariables")
  resume()
end)

test("perf: the slash verb dispatches into the lib", function()
  reset()
  NS.Slash:OnSlash("perf start")
  assertTrue(P.run, "typed command reached the lib")
  P.Cancel()
  settle()
end)
