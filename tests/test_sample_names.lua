-- tests/test_sample_names.lua — one source of sample names (FB2-RM-01 of Ka0sAddonsCommonTasks
-- docs/2026-11-24-FEEDBACK_BATCH, decision D1; LibKa0s#104, Sim minor 5; WowAddonStandards v2.120.0,
-- preview-mode's naming convention without its old rule 6).
--
-- The owner, 2026-11-24: "adopt the predefined test mode names consistently across all addon's
-- test/sim modes". Every named sample person a Ka0s addon draws (test mode, sim, preview and unlock
-- stand-ins, sample chat lines, toasts) comes from LibKa0s-Sim-1.0: Sample() for the five
-- protagonists and SampleCrowd(client, n, seed) for anyone beyond them. Range Master draws no named
-- person today: its sim is a distance, its test mode a placeholder range, and its nameplate stand-in
-- reads "Nameplate (Target)". This case holds that line: no word of the convention's shape (one
-- capitalized word starting "Sample" or "Mock") in any tracked file outside tests/, libs/ and the
-- frozen bundles, so a hand-kept name list or a hand-copied library name cannot land unseen.
--
-- NOT A PERSON. The module name Mockplate (modules/Anchors_Mockplate.lua, the stand-in nameplate)
-- has the shape and names no one; it is the one word allowed, by name.

local T = _G.RM_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local ALLOWED = { Mockplate = "the stand-in nameplate module, not a sample person" }
local SKIP = { "^libs/", "^tests/", "^docs/audits/", "^docs/reviews/", "^docs/automated-tests/",
               "^docs/perf-analysis/", "^docs/revendor/", "^docs/superpowers/" }
local BINARY = { tga = true, png = true, jpg = true, jpeg = true, ttf = true, blp = true, ogg = true, mp3 = true }

local function skipped(path)
  for _, p in ipairs(SKIP) do if path:find(p) then return true end end
  return BINARY[(path:match("%.(%w+)$") or ""):lower()] == true
end

--- Every tracked path the rule reads.
local function tracked()
  assertTrue(io.popen ~= nil, "io.popen is unavailable, so the tracked set cannot be read")
  local pipe = assert(io.popen("git ls-files"), "git ls-files gave no handle")
  local out = {}
  for line in pipe:lines() do
    if not skipped(line) then out[#out + 1] = line end
  end
  pipe:close()
  return out
end

--- Each word of the convention's shape in `text`, with its line.
local function names(text)
  local found, n = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    for _, stem in ipairs({ "Sample", "Mock" }) do
      for word in line:gmatch("%f[%a]" .. stem .. "%l+%f[%A]") do found[#found + 1] = { word = word, line = n } end
    end
  end
  return found
end

test("sample names: no sample person's name outside tests/ and libs/; the library is the one source", function()
  -- red under: a hand-kept roster ("Mockgrove", "Samplehunter") in a module, a locale or a live doc.
  local paths = tracked()
  assertTrue(#paths > 50, "the tracked set was read, got " .. #paths)
  local hits = {}
  for _, path in ipairs(paths) do
    local fh = io.open(path, "rb")
    if fh then
      local text = fh:read("*a")
      fh:close()
      for _, h in ipairs(names(text)) do
        if not ALLOWED[h.word] then hits[#hits + 1] = path .. ":" .. h.line .. " " .. h.word end
      end
    end
  end
  assertEqual(#hits, 0, "sample names belong to LibKa0s-Sim-1.0 (Sample, SampleCrowd), not this addon:\n  "
    .. table.concat(hits, "\n  "))
end)

test("sample names: the scan sees a planted name, and passes the allowed word", function()
  -- red under: a pattern that matches nothing, which would pass every tree.
  local got = names('local crowd = { "Mockgrove", "Samplehunter" }\n-- Anchors_Mockplate, Sampler, Sample, mocked\n')
  local words = {}
  for _, h in ipairs(got) do words[#words + 1] = h.word .. "@" .. h.line end
  assertEqual(table.concat(words, ","), "Samplehunter@1,Mockgrove@1,Sampler@2,Mockplate@2",
    "the planted names are found, each on its line")
  assertTrue(ALLOWED.Mockplate ~= nil, "and the module name is allowed by name")
end)
