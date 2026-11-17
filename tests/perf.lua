-- tests/perf.lua — the offline perf scenario runner (performance-§9). OUTSIDE the green gate: it is
-- run by tests/_kit/run-automated-tests.sh's `perf` suite and recorded, never used to fail a commit.
--
--   lua tests/perf.lua [--out <path>] [--label <text>]
--
-- It asserts only DETERMINISTIC quantities (allocations and call counts, never wall-clock time) and
-- ships the zero-overhead scenario: a dormant perf bracket must cost nothing measurable, which is the
-- evidence that instrumentation is free while capture is off. The v0.1.0 scaffold's one bracketed
-- path is the combat edge (core/RangeMaster.lua's OnCombatChanged, bucket `combatEdge`); the range
-- engine's ticker and range reads join this file with their buckets (the v0.1.0 plan, Task 2).
--
-- Its scenarios are not counted in docs/test-cases.md or the README's [tests] badge.

local Loader     = dofile("tests/_kit/loader.lua")
local buildMocks = dofile("tests/wow_mock.lua")

Loader.addonName = "RangeMaster"

local opts = { out = nil, label = "offline" }
do
  local i = 1
  while arg and arg[i] do
    local a = arg[i]
    if a == "--out" then opts.out = arg[i + 1]; i = i + 2
    elseif a == "--label" then opts.label = arg[i + 1] or opts.label; i = i + 2
    else
      io.stderr:write("unknown argument: " .. tostring(a) .. "\n")
      io.stderr:write("usage: lua tests/perf.lua [--out <path>] [--label <text>]\n")
      os.exit(2)
    end
  end
end

-- The same load the suite uses: the library from its XML, the addon from its TOC.
local mocks = buildMocks()
local NS = {}
Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), NS, mocks)
Loader.loadAll(Loader.tocFiles("RangeMaster.toc"), NS, mocks)
NS:InitDB()

local results, failures = {}, {}

local function assert_(cond, msg)
  if not cond then failures[#failures + 1] = msg end
  return cond
end

local function measure(name, iterations, fn)
  collectgarbage("collect")
  collectgarbage("collect")
  local kbBefore = collectgarbage("count")
  local t0 = os.clock()
  for i = 1, iterations do fn(i) end
  local elapsed = os.clock() - t0
  local kbAfter = collectgarbage("count")
  local r = {
    name         = name,
    iterations   = iterations,
    totalMs      = elapsed * 1000,
    msPerIter    = (elapsed * 1000) / iterations,
    bytesPerIter = ((kbAfter - kbBefore) * 1024) / iterations,
  }
  results[#results + 1] = r
  return r
end

local BURST = 1000

-- The combat-leave edge: no mode to end, so the pass is the bracket and one gated debug call.
local combatEdge = measure("combatEdge", BURST, function()
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
end)
assert_(combatEdge.bytesPerIter < 64,
  ("combatEdge allocates %.1f bytes/edge; an edge with nothing to end must be near-free")
    :format(combatEdge.bytesPerIter))

-- The settings read every surface makes: the schema runtime's walk, with the split cached.
local settingsRead = measure("settingsRead", BURST * 10, function()
  NS.GetSetting("visibility")
end)
assert_(settingsRead.bytesPerIter < 16,
  ("settingsRead allocates %.1f bytes/read; the read path must not allocate")
    :format(settingsRead.bytesPerIter))

-- The zero-overhead scenario: the same pass with the probe dormant and armed. A dormant bracket is
-- one upvalue read, one field read and one boolean test (performance-§2), so it must allocate no
-- more than the armed one.
local probeOff = measure("probeOverheadOff", BURST, function()
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
end)
NS.Perf.on = true
local probeOn = measure("probeOverheadOn", BURST, function()
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
end)
NS.Perf.on = false
assert_(probeOff.bytesPerIter <= probeOn.bytesPerIter + 1,
  "a dormant bracket allocated more than an armed one — the gating idiom is wrong")

print(("Ka0s Range Master \226\128\148 offline perf  (v%s, label '%s')"):format(NS.version, opts.label))
print()
print(("%-18s %10s %12s %12s %12s"):format("scenario", "iters", "ms/iter", "total-ms", "bytes/iter"))
for _, r in ipairs(results) do
  print(("%-18s %10d %12.5f %12.3f %12.1f"):format(r.name, r.iterations, r.msPerIter, r.totalMs, r.bytesPerIter))
end
print()
print("timings are for orientation only \226\128\148 compare scenarios within a run, never across machines")

if #failures > 0 then
  print()
  print(("%d assertion%s FAILED:"):format(#failures, #failures == 1 and "" or "s"))
  for _, f in ipairs(failures) do print("  - " .. f) end
end

if opts.out then
  local buckets = {}
  for _, r in ipairs(results) do
    buckets[r.name] = {
      calls        = r.iterations,
      totalMs      = r.totalMs,
      maxMs        = r.msPerIter,
      bytesPerIter = r.bytesPerIter,
    }
  end
  local record = {
    schema    = NS.Perf.SCHEMA,
    addon     = "RangeMaster",
    source    = "offline",
    version   = NS.version,
    interface = 0,          -- no client involved
    timestamp = os.time(),
    label     = opts.label,
    buckets   = buckets,
    fps       = {           -- fixed shape; an offline run has no frames to sample
      active    = { seconds = 0, frames = 0, avgFps = 0, msPerFrame = 0 },
      suspended = { seconds = 0, frames = 0, avgFps = 0, msPerFrame = 0 },
      deltaMsPerFrame = 0,
    },
    failures  = failures,
  }
  local fh, err = io.open(opts.out, "w")
  if not fh then
    io.stderr:write("cannot write " .. opts.out .. ": " .. tostring(err) .. "\n")
    os.exit(2)
  end
  fh:write(NS.Perf.EncodeJSON(record), "\n")
  fh:close()
  print("wrote " .. opts.out)
end

os.exit(#failures == 0 and 0 or 1)
