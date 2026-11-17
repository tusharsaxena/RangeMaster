-- tests/test_diagnostics.lua — this addon's half of the diagnostics dump (debug-logging-§14).
--
-- What the report IS is shared: the markers, the identity header, the per-section pcall, the cap
-- and the truncated line are LibKa0s-DebugLog-1.0's helper (libs/LibKa0s/DebugLogDiagnostics.lua)
-- and are tested in that library's own suite. The dispatcher contract (both forms, while disabled,
-- append, ungated, the markers carrying our brand, `diag` not running it) is the kit's shared case,
-- tests/_kit/test_diagnostics_contract.lua, wired to this addon's dispatcher in tests/run.lua.
--
-- What is OURS, and what this file covers: the `diagnostics` row as settings/Slash.lua spells it;
-- the sections modules/Diagnostics.lua writes, and that each reads state without changing it; the
-- stood-down wording; and the library-absent arm.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- ── helpers ────────────────────────────────────────────────────────────────────────────────

--- The report as `[tag] msg` lines, built as data (nothing reaches the console), plus the raw
--- result for the cap fields.
local function report(spec)
  local r = NS.DebugLog:BuildDiagnostics(spec)
  local lines = {}
  for i, l in ipairs(r.lines) do lines[i] = "[" .. l[1] .. "] " .. l[2] end
  return lines, r
end

local function joined(lines) return table.concat(lines, "\n  ") end

--- The first line holding `needle`, or nil.
local function find(lines, needle)
  for _, l in ipairs(lines) do
    if l:find(needle, 1, true) then return l end
  end
  return nil
end

--- The lines the helper wrote for a section that raised.
local function failures(lines)
  local out = {}
  for _, l in ipairs(lines) do
    if l:find("^%[Diag%] section .- failed:") then out[#out + 1] = l end
  end
  return out
end

-- ── the command surface ─────────────────────────────────────────────────────────────────────

-- ── the sections ────────────────────────────────────────────────────────────────────

-- One needle per fact modules/Diagnostics.lua writes; docs/debug.md lists the sections.
local ONCE = {
  "[Diag] schema: stored=",
  "[Diag] profile: ",
  "[Diag] client: ",
  "[Diag] enabled (stored)=",
  "[Diag] test mode=",
  "[Life] holds:",
  "[Life] perf: capturing=",
  "[Life] bus: ",
  "[Events] AceEvent registered:",
  "[Events] rejected events:",
  "[UI] settings panel open=",
  "[UI] launcher: registered=",
  "[UI] libraries missing:",
}

test("diagnostics: the report carries every section's facts, and no section fails", function()
  -- red under: a section dropped, renamed, or raising (the helper's per-section pcall turns a raise
  -- into one `section ... failed` line, which this counts).
  local lines = report()
  for _, needle in ipairs(ONCE) do
    assertTrue(find(lines, needle) ~= nil, "missing `" .. needle .. "` in:\n  " .. joined(lines))
  end
  assertEqual(#failures(lines), 0, "a section raised: " .. joined(failures(lines)))
end)

test("diagnostics: stood down, the events section says so rather than listing nothing", function()
  NS.SetByPath("enabled", false)
  local lines = report()
  NS.SetByPath("enabled", true)
  assertTrue(find(lines, "[Events] stood down: every registration released") ~= nil, joined(lines))
end)

test("diagnostics: the row sits straight after debug and its text is routed through NS.L", function()
  local debugAt, diagAt
  for i, entry in ipairs(NS.COMMANDS) do
    if entry[1] == "debug" then debugAt = i end
    if entry[1] == "diagnostics" then diagAt = i end
  end
  assertTrue(diagAt ~= nil, "NS.COMMANDS has a `diagnostics` row")
  assertEqual(diagAt, debugAt + 1, "straight after `debug`")
  local desc = NS.COMMANDS[diagAt][2]
  assertEqual(rawget(NS.L, desc), desc, "the description is a key locales/enUS.lua sets")
end)

test("diagnostics: the sections change nothing, and the run only turns logging on", function()
  -- debug-logging-§14: no hold, no event, no timer, no stand-up, no settings panel, no Clear.
  NS.SetByPath("enabled", true)
  NS.DebugLog:Show()
  NS.DebugLog:SetEnabled(false)
  local registrations = #M.__registrations()
  local timers = #M.__timers
  local holds = table.concat(NS.lifecycle:Holds(), ",")
  local opened, cleared = 0, 0
  local open, clear = NS.OpenOptionsPanel, NS.DebugLog.Clear
  NS.OpenOptionsPanel = function() opened = opened + 1 end
  NS.DebugLog.Clear = function(...) cleared = cleared + 1 return clear(...) end
  local ok, err = pcall(NS.DebugLog.RunDiagnostics, NS.DebugLog)
  NS.OpenOptionsPanel, NS.DebugLog.Clear = open, clear
  NS.DebugLog:Hide()
  assertTrue(ok, tostring(err))
  assertEqual(#M.__registrations(), registrations, "no registration made or dropped")
  assertEqual(#M.__timers, timers, "no timer armed")
  assertEqual(table.concat(NS.lifecycle:Holds(), ","), holds, "no hold taken or released")
  assertTrue(NS.State.debug, "a run leaves logging on, never off")
  assertEqual(opened, 0, "the settings panel was not opened")
  assertEqual(cleared, 0, "the console was not cleared")
  NS.DebugLog:SetEnabled(false)
end)

test("diagnostics: the session's rejected events are folded into the report", function()
  -- `/rm debug events` stays as a topic (debug-logging-§4's MAY); the report carries the same list,
  -- so a pasted report does not need a second command.
  -- red under: a report that leaves NS.State.rejectedEvents out.
  local list = NS.State.rejectedEvents
  list[#list + 1] = "AT_DIAGNOSTICS_PROBE_EVENT"
  local lines = report()
  list[#list] = nil
  assertTrue(find(lines, "AT_DIAGNOSTICS_PROBE_EVENT") ~= nil, joined(lines))
end)

test("diagnostics: an over-cap report ends in the truncated line, then the end marker", function()
  -- red under: sections that write around the helper's writer (hand-rolled Add calls would not be
  -- counted or dropped), which is anti-pattern #90.
  local lines, r = report({ maxLines = 12 })
  assertTrue(r.capped, "the cap bit")
  assertTrue(lines[#lines - 1]:find("^%[Diag%] truncated: %d+ line%(s%) omitted") ~= nil,
    lines[#lines - 1])
  assertTrue(lines[#lines]:find(NS.Constants.BRAND .. " diagnostics end: 12 line(s)", 1, true)
    ~= nil, lines[#lines])
end)

test("diagnostics: the chat line is ours to localize and names the line count", function()
  -- debug-logging-§14 (STD-09 / STD-13): the one chat line is localized; the report body is not.
  -- The descriptor hands the library's DIAG_WRITTEN key a string from NS.L, never NS.L itself,
  -- whose key-echo fallback would answer every other key with its own name.
  -- red under: dropping the descriptor's `L` entry (the line would still read, but no longer from
  -- this addon's locale table), or a second chat line.
  local key = "Diagnostic report written to the debug console: %d lines. Use Copy to share it."
  assertEqual(rawget(NS.L, key), key, "locales/enUS.lua sets the key")
  assertEqual(NS.DebugLog:Text("DIAG_WRITTEN"), key, "the descriptor routes it to the library")
  M.__resetPrinted()
  local n = NS.DebugLog:RunDiagnostics()
  NS.DebugLog:Hide()
  local out = {}
  for _, line in ipairs(M.__printed()) do
    if line:find("Diagnostic report", 1, true) then out[#out + 1] = line end
  end
  assertEqual(#out, 1, "one chat line: " .. table.concat(M.__printed(), " / "))
  assertTrue(out[1]:find(key:format(n), 1, true) ~= nil, out[1])
end)

test("diagnostics: with the library absent both forms print the one absent line", function()
  -- debug-logging-§14 (STD-14). The sections module loads without the library, and the degraded
  -- dispatcher routes both forms to the DebugLog stub, which says what is missing.
  -- red under: a degraded load that raises in modules/Diagnostics.lua, or a form that goes silent.
  local NS2, M2 = dofile("tests/degraded_env.lua")()
  assertEqual(type(NS2.Diagnostics and NS2.Diagnostics.Sections), "function",
    "modules/Diagnostics.lua loaded without the library")
  assertEqual(type(NS2.Diagnostics.Sections()), "table")
  local want = "/rm diagnostics is unavailable: the LibKa0s library did not load."
  for _, form in ipairs({ "diagnostics", "debug diagnostics" }) do
    M2.__resetPrinted()
    NS2.Slash:OnSlash(form)
    local hits = 0
    for _, line in ipairs(M2.__printed()) do
      if line:find(want, 1, true) then hits = hits + 1 end
    end
    assertEqual(hits, 1, "/rm " .. form .. ": " .. table.concat(M2.__printed(), " / "))
  end
  assertFalse(NS2.DebugLog:DebugVerb("events"), "the stub leaves the topic words to the host")
end)
