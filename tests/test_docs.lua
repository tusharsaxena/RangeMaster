-- tests/test_docs.lua — the shipped prose is checkable, so it is checked.
--
-- What this checks: README.md carries no angle-bracket placeholders (CurseForge strips `<path>` even
-- inside backticks), carries documentation-§1 item 9's `## Reporting a bug` text verbatim and no
-- numbered list; docs/ARCHITECTURE.md's Tier 2 map agrees with docs/; and docs/smoke-tests.md carries
-- its non-English-client section. The US-English prose gate is the kit's (tests/_kit/test_prose.lua).

local T = _G.RM_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local function readFile(path)
  local f = io.open(path, "r")
  assertTrue(f ~= nil, "cannot open " .. path .. " (tests run from the repo root)")
  local body = f:read("*a")
  f:close()
  return body
end


-- ── README: no angle-bracket placeholders ──────────────────────────────────────────────────

-- The tags markdown genuinely wants in this README. Anything else between angle brackets is a
-- placeholder that CurseForge will eat.
local ALLOWED_TAGS = { br = true }

test("README.md carries no angle-bracket argument placeholders", function()
  local body = readFile("README.md")
  local lineNo, offenders = 0, {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    lineNo = lineNo + 1
    for tag in line:gmatch("<([^<>]*)>") do
      if not ALLOWED_TAGS[tag:lower():match("^/?%s*(%a*)") or ""] then
        offenders[#offenders + 1] = "README.md:" .. lineNo .. " <" .. tag .. ">"
      end
    end
  end
  assertEqual(#offenders, 0,
    "CurseForge strips these even inside backticks; write the argument bare -- "
      .. table.concat(offenders, "; "))
end)

-- ── README: the Reporting a bug section is the standard's text ──────────────────────────────

-- documentation-§1 item 9 fixes this section's body word for word, with the addon's real slash.
-- It names no destination and carries no link: players send the report to the owner privately
-- with their bug report. The section sits between Troubleshooting and Issues and feature
-- requests, and a Troubleshooting row points at it.
local REPORTING_BODY = table.concat({
  "- Type `/rm debug on` and reproduce the bug.",
  "- Type `/rm diagnostics`.",
  "- If the debug window isn't open, open it with `/rm debug`. Press **Copy**, copy the entire "
    .. "output, and include it with your bug report.",
  "",
  "The report is added after the debug trace in the same window, so one copy carries both.",
}, "\n")

local REPORTING_ROW =
  "| Something looks wrong and I want to report it | Follow [Reporting a bug](#reporting-a-bug) below. |"

test("README.md carries ## Reporting a bug with the standard's text, placed and pointed at", function()
  local body = readFile("README.md"):gsub("\r", "")
  local tIdx = body:find("\n## Troubleshooting\n", 1, true)
  local rIdx = body:find("\n## Reporting a bug\n", 1, true)
  local iIdx = body:find("\n## Issues and feature requests\n", 1, true)
  assertTrue(rIdx ~= nil, "README.md has no `## Reporting a bug` section")
  assertTrue(tIdx ~= nil and iIdx ~= nil and tIdx < rIdx and rIdx < iIdx,
    "`## Reporting a bug` must sit between Troubleshooting and Issues and feature requests")
  local section = body:match("\n## Reporting a bug\n\n(.-)\n+## ")
  assertEqual(section, REPORTING_BODY, "the section body must be the standard's text with /rm")
  assertTrue(not section:lower():find("github", 1, true) and not section:find("](", 1, true),
    "the section names no destination and carries no link")
  assertTrue(body:sub(tIdx, rIdx):find(REPORTING_ROW, 1, true) ~= nil,
    "Troubleshooting carries the row that points at the section")
end)

-- ── README: bullets, never numbered lists ───────────────────────────────────────

-- documentation-§1 (standard v2.72.0): CurseForge's description page does not render a numbered
-- list, so every list in README.md is a `- ` bullet list and the words carry any order. Fenced
-- code blocks are skipped; the check is on the rendered prose.
test("README.md carries no numbered list", function()
  local body = readFile("README.md"):gsub("\r", "")
  local offenders, inFence, n = {}, false, 0
  for line in (body .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    if line:match("^%s*```") then
      inFence = not inFence
    elseif not inFence and line:match("^%s*%d+[.)]%s") then
      offenders[#offenders + 1] = "line " .. n
    end
  end
  assertEqual(#offenders, 0, "numbered list lines in README.md: " .. table.concat(offenders, ", "))
end)

-- ── The Tier 2 documentation map says what docs/ actually holds ─────────────────

-- `documentation-§3` files a conditional doc as Present or as Not applicable, and Not applicable is
-- a valid state that MUST be stated rather than left to an empty directory listing. What it must not
-- be is wrong: a row reading Not applicable beside a trigger that has fired is indistinguishable, to
-- everything except a human re-deriving the trigger, from a doc nobody has written yet. That is
-- exactly what this repo carried -- seventeen verbs and a `PROFILE_VERBS` tree filed as "no
-- subcommand tree" -- and it survived three audits because nothing checked it.
--
-- So the two halves are checked against the disk. Present must name a file; Not applicable must not.
-- The trigger itself is prose and stays a human's to read; the status is not, and this is the half a
-- machine can hold.

test("every Tier 2 documentation-map row agrees with docs/", function()
  local body = readFile("docs/ARCHITECTURE.md")
  local section = body:match("### Conditional[^\n]*\n(.-)\n###")
  assertTrue(section ~= nil,
    "docs/ARCHITECTURE.md has no `### Conditional ... Tier 2` section to read")

  local rows, offenders = 0, {}
  for doc, status in section:gmatch("|%s*`([^`]+)`%s*|%s*([^|]-)%s*|") do
    if status == "Present" or status == "Not applicable" then
      rows = rows + 1
      local path = "docs/" .. doc
      local f = io.open(path, "r")
      local exists = f ~= nil
      if f then f:close() end
      if status == "Present" and not exists then
        offenders[#offenders + 1] = doc .. " is filed Present and does not exist"
      elseif status == "Not applicable" and exists then
        offenders[#offenders + 1] = doc .. " exists and is filed Not applicable"
      end
    end
  end

  assertTrue(rows >= 5, "read only " .. rows .. " Tier 2 rows -- the table shape changed")
  assertEqual(#offenders, 0, "the map and the directory disagree: "
    .. table.concat(offenders, "; "))
end)


-- ── The US-English gate is the KIT's now ──────────────────────────────────────────────
--
-- It used to live here: a BRITISH list, an ALLOWED list, a walk over the addon's own files, and
-- the cases over them. All of it is gone, replaced by one line in tests/run.lua declaring
-- `{ name = "test_prose", dir = "tests/_kit/" }` (LibKa0s kit revision 24). localization-§5 says
-- wire the kit's gate or your own and NEVER both, because two gates over one rule is two copies
-- of a list each required to be carried whole -- and the collection proved the cost: seven repos
-- had written this by hand under three different filenames before the kit shipped one.
--
-- COVERAGE WENT UP ON THE SWAP. This file's version walked a glob of the addon's own source. The
-- kit's reads the tracked set out of git, so the TOC, the docs, the locale files and .luacheckrc
-- are held to the same rule, and its exclusions are a named list rather than whatever the glob
-- happened to miss. Anything this repo must NOT correct would go in an optional tests/prose_waivers.lua (none today),
-- per file and per word, with the reason beside it.

-- ── The smoke suite's non-English-client section ───────────────────────────────

-- WHAT IT PROVES, AND WHAT IT DOES NOT. That `docs/smoke-tests.md` still carries a section
-- addressed to a non-English client, that the section names the locale to run it on, and that it
-- says what a failure looks like rather than only what a pass does. It proves nothing whatever
-- about that section having been RUN -- a checklist is a checklist, and this repository has no
-- client. What it stops is the section quietly disappearing, or shrinking to a heading with a
-- sentence under it, in a repository whose every other doc gate is about structure too.
--
-- WHY IT IS WORTH A CASE. The base mock's globals are enUS, so a path that keys off a localized
-- string is green in this suite whether it is right or wrong: the test and the bug agree. Six of
-- the collection's nine addons had no locale step at all when `M5-08` was written, and the header
-- of this very file says "Run on a live Retail ... English client" -- an instruction that was, on
-- its own, the whole locale policy. A section nothing reads is a section that goes.
--
-- The pass/fail vocabulary is matched loosely on purpose. This suite's sections say "the finding"
-- where others say "Fail", and pinning one spelling would redden the tree for a rewording.
local LOCALE_HEADING = "[Nn]on%-English client"
local FAILURE_WORDS = { "the finding", "Fail", "failure", "Failure" }

test("docs/smoke-tests.md carries a non-English-client section", function()
  local body = readFile("docs/smoke-tests.md")

  local capture, level, section = false, nil, {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local hashes = line:match("^(#+)%s")
    if hashes and capture and #hashes <= level then break end
    if hashes and not capture and line:match(LOCALE_HEADING) then
      capture, level = true, #hashes
    end
    if capture then section[#section + 1] = line end
  end
  assertTrue(capture, "docs/smoke-tests.md has no heading naming a non-English client. The step is "
    .. "unconditional (M5-08): where the addon reads nothing localized the section still ships and "
    .. "says what it checked and why it came back empty")

  local text = table.concat(section, "\n")
  assertTrue(text:find("deDE", 1, true) or text:find("frFR", 1, true),
    "the non-English-client section names no client to run it on -- deDE and frFR are the two the "
    .. "collection's other locale steps use")

  local named = false
  for _, word in ipairs(FAILURE_WORDS) do
    if text:find(word, 1, true) then named = true break end
  end
  assertTrue(named, "the non-English-client section says what passing looks like and never what "
    .. "failing looks like. A step whose only outcome is 'it works' is unfalsifiable in a client "
    .. "the operator booted specially")

  assertTrue(#section >= 10, "the non-English-client section is " .. #section .. " lines -- a "
    .. "heading with a sentence under it records the gap as coverage, which is the failure M5-08 "
    .. "was filed for")
end)
