-- tests/perf.lua — the offline perf scenario runner (performance-§9). OUTSIDE the green gate: it is
-- run by tests/_kit/run-automated-tests.sh's `perf` suite and recorded, never used to fail a commit.
--
--   lua tests/perf.lua [--out <path>] [--label <text>]
--
-- It asserts only DETERMINISTIC quantities (allocations and call counts, never wall-clock time) and
-- ships the zero-overhead scenario: a dormant perf bracket must cost nothing measurable, which is the
-- evidence that instrumentation is free while capture is off. The bracketed paths are the combat
-- edge (core/RangeMaster.lua's OnCombatChanged, bucket `combatEdge`), the range read on a memo miss
-- (modules/Range.lua, `range.get`), the range ticker's tick (modules/Ticker.lua, `ticker.tick`),
-- the last measured at the design spec's load: ten containers over four units plus twenty plates,
-- the renderer's fan-out over those ten containers and over a nameplates container's twenty
-- per-plate instances (modules/Container.lua, `container.render`), the same twenty plates on a rule
-- band set whose bands the anchors' spell answers decide (modules/BandSets.lua's Resolve through
-- modules/Range.lua's memo), and the cursor follow's one
-- OnUpdate over three cursor containers (modules/Anchors_Cursor.lua, `cursor.follow`).
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
-- LibRangeCheck-3.0, by its own TOC line as tests/run.lua loads it, so modules/Range.lua captures
-- the real library at load.
Loader.loadAll({ "libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua" }, NS, mocks)
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

-- The range engine. LibRangeCheck's own GetRange is the library's cost and is measured upstream;
-- here it answers a fixed bracket, so what is measured is ours: the guards, the memo and the
-- RANGE_UPDATED change test. Ten containers over target, focus, pet and mouseover, and twenty
-- enemy plates (design spec 6).
local LRC = mocks.LibStub("LibRangeCheck-3.0", true)
local farther = false
LRC.GetRange = function() if farther then return 30, 35 end return 20, 25 end
local WATCHES = { target = 4, focus = 2, pet = 2, mouseover = 2 }
for unit, n in pairs(WATCHES) do
  mocks.__unitExists[unit] = true
  for _ = 1, n do NS.Ticker.Watch(unit) end
end
for i = 1, 20 do
  mocks.__unitExists["nameplate" .. i] = true
  NS.Ticker.Watch("nameplate" .. i)
end
local tickFn = NS.Ticker.__handle().fn

-- A memo miss: a new tick, one read. Reuses the token's memo entry, so it must not allocate.
local rangeGet = measure("range.get", BURST * 10, function()
  NS.Range.BeginTick()
  NS.Range.Get("target")
end)
assert_(rangeGet.bytesPerIter < 16,
  ("range.get allocates %.1f bytes/read; a memo miss must reuse the token's entry")
    :format(rangeGet.bytesPerIter))

-- A memo hit: the second container on a unit inside one tick.
local rangeHit = measure("range.get.hit", BURST * 10, function()
  NS.Range.Get("target")
end)
assert_(rangeHit.bytesPerIter < 1,
  ("a memo hit allocates %.1f bytes/read; it must be a table read"):format(rangeHit.bytesPerIter))

-- The steady state: 24 units, nothing moved, so nothing is sent.
local tickQuiet = measure("ticker.tick", BURST, function() tickFn() end)
assert_(tickQuiet.bytesPerIter < 64,
  ("ticker.tick allocates %.1f bytes/tick with nothing moving; a quiet tick must be near-free")
    :format(tickQuiet.bytesPerIter))

-- Every unit moving every tick: 24 RANGE_UPDATED sends per tick (orientation only, not asserted:
-- the send is AceEvent's).
measure("ticker.tick.moving", BURST, function(i)
  farther = i % 2 == 0
  tickFn()
end)

for unit, n in pairs(WATCHES) do for _ = 1, n do NS.Ticker.Unwatch(unit) end end
for i = 1, 20 do NS.Ticker.Unwatch("nameplate" .. i) end
assert_(not NS.Ticker.IsRunning(), "the ticker did not stop when the last watch went")

-- The renderer (modules/Container.lua): the same ten containers, drawn. A quiet tick sends nothing,
-- so it renders nothing; a moving one re-renders every instance (bucket container.render), each
-- setting its text once and recoloring only on a band change. (20, 25) and (30, 35) are two bands
-- of the default set, so every moving tick is the worst case: a new band on every instance.
local ids = {}
for unit, n in pairs(WATCHES) do
  for _ = 1, n do ids[#ids + 1] = NS.CM.Create(unit) end
end
NS.CM.FlushPending()
farther = false
tickFn = NS.Ticker.__handle().fn
local renderQuiet = measure("render.quiet", BURST, function() tickFn() end)
assert_(renderQuiet.bytesPerIter < 64,
  ("a quiet tick with ten containers allocates %.1f bytes; nothing moved, so nothing may be drawn")
    :format(renderQuiet.bytesPerIter))
measure("container.render", BURST, function(i)
  farther = i % 2 == 0
  tickFn()
end)

-- The dormant-bracket scenario (performance-§2, §9): with capture off, the hot paths are compared
-- against NO instrumentation at all, by call count. A moving tick over the ten containers runs the
-- ticker.tick, range.get and container.render brackets, and the combat edge runs combatEdge; with
-- Perf.on false not one of them may read the clock or reach Perf.Note. The armed pass is the control:
-- the same work with Perf.on true must count calls, or the counters measure nothing.
-- red under: a bracket that reads debugprofilestop before testing Perf.on.
local function countBracketCalls(on, iterations)
  local realClock, realNote, n = mocks.debugprofilestop, NS.Perf.Note, 0
  mocks.debugprofilestop = function(...) n = n + 1; return realClock(...) end
  NS.Perf.Note = function(...) n = n + 1; if on then return realNote(...) end end
  NS.Perf.on = on
  local ok, err = pcall(function()
    for i = 1, iterations do
      farther = i % 2 == 0
      tickFn()
      NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
    end
  end)
  NS.Perf.on = false
  mocks.debugprofilestop, NS.Perf.Note = realClock, realNote
  if not ok then error(err, 0) end
  return n
end
local dormantCalls = countBracketCalls(false, BURST)
assert_(dormantCalls == 0,
  ("with capture off the hot paths made %d clock reads or Perf.Note calls; a dormant bracket must make none")
    :format(dormantCalls))
assert_(countBracketCalls(true, 10) > 0,
  "the armed control counted no bracket calls; the dormant count above proves nothing")
for _, id in ipairs(ids) do NS.CM.Delete(id) end
NS.CM.FlushPending()
assert_(not NS.Ticker.IsRunning(), "the ticker did not stop when the last container went")

-- The nameplates unit (modules/Anchors_Nameplate.lua): one `nameplates` container over the twenty
-- enemy plates is twenty per-plate instances, each on its own token, read once per tick like any
-- unit. A quiet tick draws nothing; a moving one re-renders all twenty (bucket container.render).
for i = 1, 20 do
  local token = "nameplate" .. i
  local plate = mocks.CreateFrame("Frame")
  rawset(plate, "IsForbidden", function() return false end)
  mocks.__plates[token] = plate
  NS.Plates.Added(token)
end
local realAttack = mocks.UnitCanAttack
mocks.UnitCanAttack = function() return true end
local platesId = NS.CM.Create("nameplates")
NS.CM.FlushPending()
local _, plateCount = NS.Container.__plateCounts()
assert_(plateCount == 20, ("a nameplates container over 20 hostile plates holds %d instances"):format(plateCount))
farther = false
tickFn = NS.Ticker.__handle().fn
-- The mock ticker re-queues its handle on every fire; emptied in place first, so the queue's own
-- growth (a harness cost, not the addon's) does not land inside the measured window.
for i = #mocks.__timers, 1, -1 do mocks.__timers[i] = nil end
local platesQuiet = measure("render.plates.quiet", BURST, function() tickFn() end)
assert_(platesQuiet.bytesPerIter < 64,
  ("a quiet tick over 20 plate instances allocates %.1f bytes; nothing moved, so nothing may be drawn")
    :format(platesQuiet.bytesPerIter))
measure("render.plates", BURST, function(i)
  farther = i % 2 == 0
  tickFn()
end)
NS.CM.Delete(platesId)
NS.CM.FlushPending()

-- The same twenty plates on a rule band set (dynamic-bands plan D7): the Forever hunter shape
-- (MELEE melee, DEAD gap, AUTO ranged, OOR beyond) on a hunter whose anchors are known, so every
-- instance's band is decided by the anchors' C_Spell.IsSpellInRange answers through the Range memo.
-- A quiet tick re-resolves each shown instance's band (the steady read), asking each anchor once per
-- plate per tick; a moving one flips Auto Shot with the bracket, so every plate swaps AUTO for OOR.
do
  local client, savedClass = NS.Compat.ClientKey(), mocks.__context.classToken
  local seeds = NS.SpellSeeds[client]
  local realSeed = seeds.HUNTER
  local book, spell = mocks.C_SpellBook, mocks.C_Spell
  local real = { book.IsSpellKnown, spell.IsSpellUsable, spell.GetSpellInfo, spell.IsSpellInRange }
  local INFO = {
    [2973] = { name = "Raptor Strike", iconID = 1, castTime = 0, spellID = 2973, minRange = 0, maxRange = 5 },
    [75]   = { name = "Auto Shot", iconID = 1, castTime = 0, spellID = 75, minRange = 8, maxRange = 41 },
  }
  INFO["Raptor Strike"], INFO["Auto Shot"] = INFO[2973], INFO[75]
  local asked = 0
  mocks.__context.classToken = "HUNTER"
  seeds.HUNTER = { chips = {}, ladder = {}, anchors = { melee = { 2973 }, ranged = { 75 } } }
  book.IsSpellKnown = function(id) return INFO[id] ~= nil end
  spell.IsSpellUsable = function() return true, false end
  spell.GetSpellInfo = function(id) return INFO[id] end
  spell.IsSpellInRange = function(id)
    asked = asked + 1
    if id == 75 then return not farther end
    return false
  end
  NS.Range.__rebuildNow()
  local ruleSet = NS.BandSets.Create("Perf rules", {
    { from = 0, to = 5, label = "MELEE", rule = { type = "spell", role = "melee" } },
    { from = 5, to = 8, label = "DEAD", rule = { type = "gap" } },
    { from = 8, to = 35, label = "AUTO", rule = { type = "spell", role = "ranged" } },
    { from = 35, label = "OOR", rule = { type = "beyond" } },
  })
  local rulesId = NS.CM.Create("nameplates", { bandSet = ruleSet })
  NS.CM.FlushPending()
  _, plateCount = NS.Container.__plateCounts()
  assert_(plateCount == 20, ("a rule-band nameplates container holds %d instances"):format(plateCount))
  farther = false
  tickFn = NS.Ticker.__handle().fn
  for i = #mocks.__timers, 1, -1 do mocks.__timers[i] = nil end
  asked = 0
  tickFn()
  assert_(asked > 0, "a tick over rule bands asked no anchor; the scenario measures the yard path")
  assert_(asked <= 20 * 2, ("a tick over 20 rule-band plates made %d range calls; the memo allows one per anchor per plate")
    :format(asked))
  local rulesQuiet = measure("render.plates.rules.quiet", BURST, function() tickFn() end)
  assert_(rulesQuiet.bytesPerIter < 64,
    ("a quiet tick over 20 rule-band plates allocates %.1f bytes; the rule path must not allocate")
      :format(rulesQuiet.bytesPerIter))
  measure("render.plates.rules", BURST, function(i)
    farther = i % 2 == 0
    tickFn()
  end)
  NS.CM.Delete(rulesId)
  NS.CM.FlushPending()
  NS.BandSets.Delete(ruleSet)
  seeds.HUNTER = realSeed
  book.IsSpellKnown, spell.IsSpellUsable, spell.GetSpellInfo, spell.IsSpellInRange = real[1], real[2], real[3], real[4]
  mocks.__context.classToken = savedClass
  NS.Range.__rebuildNow()
  farther = false
end
for i = 1, 20 do
  NS.Plates.Removed("nameplate" .. i)
  mocks.__plates["nameplate" .. i] = nil
end
mocks.UnitCanAttack = realAttack
_, plateCount = NS.Container.__plateCounts()
assert_(plateCount == 0, "the plate instances outlived their container")

-- The cursor follow (modules/Anchors_Cursor.lua, bucket cursor.follow): three cursor containers,
-- one shared OnUpdate. A frame places each shown container once; it must not allocate.
local cursorIds = {}
for i = 1, 3 do cursorIds[i] = NS.CM.Create("target", { anchor = { mode = "cursor" } }) end
NS.CM.FlushPending()
local driver = NS.Anchors.Cursor.__driver()
local followFn = driver and driver:GetScript("OnUpdate")
-- The kit's frame stub answers a method it does not define with a fresh closure on each access,
-- which is the harness allocating, not the addon: the three placement calls are defined plainly.
local function noop() end
for _, id in ipairs(cursorIds) do
  local f = NS.Container.Get(id).frame
  rawset(f, "ClearAllPoints", noop)
  rawset(f, "SetPoint", noop)
end
rawset(mocks.UIParent, "GetEffectiveScale", function() return 1 end)
assert_(followFn ~= nil, "three shown cursor containers armed no follow")
if followFn then
  local follow = measure("cursor.follow", BURST * 10, function(i)
    mocks.__cursor[1], mocks.__cursor[2] = i % 800, i % 600
    followFn(driver, 0.016)
  end)
  assert_(follow.bytesPerIter < 16,
    ("the cursor follow allocates %.1f bytes/frame; a per-frame pass must not allocate"):format(follow.bytesPerIter))
end
rawset(mocks.UIParent, "GetEffectiveScale", nil)
for _, id in ipairs(cursorIds) do
  local f = NS.Container.Get(id).frame
  rawset(f, "ClearAllPoints", nil)
  rawset(f, "SetPoint", nil)
  NS.CM.Delete(id)
end
NS.CM.FlushPending()
assert_(driver == nil or driver:GetScript("OnUpdate") == nil, "the follow stayed armed with no cursor container")

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
print(("%-26s %10s %12s %12s %12s"):format("scenario", "iters", "ms/iter", "total-ms", "bytes/iter"))
for _, r in ipairs(results) do
  print(("%-26s %10d %12.5f %12.3f %12.1f"):format(r.name, r.iterations, r.msPerIter, r.totalMs, r.bytesPerIter))
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
