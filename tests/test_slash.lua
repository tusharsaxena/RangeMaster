local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertNil

-- settings/Slash.lua captured `local print = NS.Print` at load, so the chat output can't be
-- intercepted by swapping NS.Print. Instead capture at the sink: NS.Print writes to
-- DEFAULT_CHAT_FRAME:AddMessage, so overriding that method on the mock frame records every line.
local function capture(fn)
  local out = {}
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local old = rawget(cf, "AddMessage")
  cf.AddMessage = function(_, msg) out[#out + 1] = msg end
  local ok, err = pcall(fn)
  cf.AddMessage = old  -- nil restores the metatable no-op
  if not ok then error(err) end
  return out
end

-- Strip WoW color escapes (`|cAARRGGBB` … `|r`) so assertions match the plain text regardless
-- of the schema-output color scheme (slash-commands-§5): gold key + white value, etc.
local function stripColor(s)
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

test("NS.Print survives AceConsole's embed and stays the [RM]-prefixed printer", function()
  -- Regression (real in-game bug): NewAddon(NS, …, "AceConsole-3.0") embeds AceConsole's :Print
  -- mixin onto NS, clobbering the custom NS.Print core/CoreSetup.lua took off LibKa0s-Core.
  -- core/RangeMaster.lua must
  -- reclaim it from the pristine NS.Util.print. Without that, every /rm line loses the [RM] tag and
  -- gains a trailing colon (AceConsole renders the message as "|cff33ff99<msg>|r:").
  assertTrue(NS.Print == NS.Util.print,
    "NS.Print must be the custom Util.print, not AceConsole's embedded mixin")
  local out = capture(function() NS.Print("regression check") end)
  assertTrue(out[1]:find("[RM]", 1, true) ~= nil, "carries the [RM] tag: " .. tostring(out[1]))
  assertTrue(stripColor(out[1]):find(":%s*$") == nil, "no trailing colon: " .. tostring(out[1]))
end)

test("bare /rm opens the settings panel through the config verb, not the help index", function()
  -- LibKa0s-Slash-1.0 minor 11 (slash-commands-§4): an empty or whitespace-only line runs the
  -- `config` handler, whose NS.OpenOptionsPanel opens the landing page. Spied at the NS seam the
  -- handler reads at call time, so the assertion is the route and not the headless no-op.
  local orig, opened = NS.OpenOptionsPanel, 0
  NS.OpenOptionsPanel = function() opened = opened + 1 end
  local ok, err = pcall(function()
    for _, line in ipairs({ "", "   ", "\t " }) do
      local before = opened
      local out = capture(function() NS.Slash:OnSlash(line) end)
      assertEqual(opened, before + 1, ("input %q opens the panel once"):format(line))
      assertEqual(#out, 0, ("input %q prints nothing, help included"):format(line))
    end
  end)
  NS.OpenOptionsPanel = orig
  if not ok then error(err) end
end)

test("/rm help prints the help index: header + one row per command", function()
  local out = capture(function() NS.Slash:OnSlash("help") end)
  assertEqual(#out, #NS.COMMANDS + 1)
  assertTrue(out[1]:find("slash commands") ~= nil, "first line is the header")
  -- No chat line the addon prints ends in a trailing colon (slash-commands-§4 house style).
  for _, line in ipairs(out) do
    assertTrue(stripColor(line):find(":%s*$") == nil, "no trailing colon: " .. line)
  end
end)

test("unknown verb prints 'unknown command' then the help index", function()
  local out = capture(function() NS.Slash:OnSlash("bogus") end)
  assertTrue(out[1]:find("unknown command 'bogus'") ~= nil, out[1])
  assertEqual(#out, #NS.COMMANDS + 2)  -- error line + header + one row per command
end)

test("/rm version prints the addon version (slash-commands-§3)", function()
  -- The standalone `version` verb must exist in NS.COMMANDS and print the running
  -- version on its own line. It reads the TOC through the NS.Version seam, which falls back to
  -- NS.version; headless no metadata API is exposed at all, so this resolves to the constant.
  local hasVersion = false
  for _, entry in ipairs(NS.COMMANDS) do
    if entry[1] == "version" then hasVersion = true break end
  end
  assertTrue(hasVersion, "NS.COMMANDS has a standalone 'version' verb")

  local expected = "v" .. NS.Version()
  local out = capture(function() NS.Slash:OnSlash("version") end)
  assertEqual(#out, 1)
  assertTrue(stripColor(out[1]):find(expected, 1, true) ~= nil,
    "prints the running version: " .. tostring(out[1]))
end)

test("/rm list uses the mandated color scheme (slash-commands-§5)", function()
  local out = capture(function() NS.Slash:OnSlash("list") end)
  -- Header: green (33ff99), no trailing colon.
  assertTrue(out[1]:find("|cff33ff99Available settings|r", 1, true) ~= nil, out[1])
  local sawGroup, sawRow = false, false
  for _, line in ipairs(out) do
    if line:find("|cff3399ff%[%w+%]|r") then sawGroup = true end        -- [page] azure
    if line:find("|cFFFFFF00%S+|r = |cFFFFFFFF") then sawRow = true end   -- gold key + white value
    assertTrue(stripColor(line):find(":%s*$") == nil, "no trailing colon: " .. line)
  end
  assertTrue(sawGroup, "at least one steel-blue [page] group header")
  assertTrue(sawRow, "at least one gold-key / white-value row")
end)

test("/rm options is aliased to /rm config (no unknown-command error)", function()
  -- config calls NS.OpenOptionsPanel, which is a no-op headlessly (no Settings category); the
  -- point is that 'options' resolves to a known verb rather than the unknown-command path.
  local out = capture(function() NS.Slash:OnSlash("options") end)
  for _, line in ipairs(out) do
    assertTrue(line:find("unknown command") == nil, "options must not be unknown")
  end
end)

test("/rm config in combat refuses with a gray notice (options-ui-§2)", function()
  local saved = T.mocks.InCombatLockdown
  T.mocks.InCombatLockdown = function() return true end
  NS.State.panelOpenPending = nil

  local out = capture(function() NS.Slash:OnSlash("config") end)
  assertTrue(out[1] ~= nil and out[1]:find("cannot open settings during combat", 1, true) ~= nil,
    "in combat the open must REFUSE with the canonical gray notice, not defer")
  assertTrue(NS.State.panelOpenPending == nil,
    "refusal must NOT defer-and-replay (no pending flag set)")

  T.mocks.InCombatLockdown = saved
end)

test("OpenOptionsPanel logs [Cfg] refused in combat", function()
  local saved = T.mocks.InCombatLockdown
  T.mocks.InCombatLockdown = function() return true end
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  NS.OpenOptionsPanel()
  NS.State.debug = false
  T.mocks.InCombatLockdown = saved
  local last = NS.DebugLog.buffer[#NS.DebugLog.buffer]
  assertTrue(#NS.DebugLog.buffer > before and last:find("[Cfg]", 1, true) ~= nil
    and last:find("refused", 1, true) ~= nil, "a [Cfg] refused line is logged in combat")
end)

-- -- the `L` trap -----------------------------------------------------------------------------

test("the schema CLI's list header the library renders is prose, not its own STRINGS key",
  function()
  -- The `SlashLib:New` descriptor in settings/Slash.lua omits `L`. `/rm list` is the shortest path from a user
  -- keystroke to a library-owned string: BuildListLines opens with Text("LIST_HEADER"), so the
  -- first captured chat line IS the rendered result. Driven through NS.Slash:OnSlash rather than
  -- the instance, because `cli` is a file-local and the dispatcher is the only real accessor.
  -- red under: giving the descriptor an `L` that answers LIST_HEADER with "LIST_HEADER".
  local out = capture(function() NS.Slash:OnSlash("list") end)
  assertTrue(#out > 0, "/rm list must print")
  -- Strip the addon's own chat tag and the color escapes so what is left is the library's string.
  local header = out[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*%[%u+%]%s*", "")
  assertTrue(header ~= "", "the list header must not be empty")
  assertNil(header:match("^[A-Z][A-Z0-9_]+$"),
    "the list header resolved to prose, not to its own key (got '" .. header .. "')")
end)





-- A library-free build, loaded once (tests/degraded_env.lua), with the one-shot "library missing"
-- banner burnt so it never counts as a verb's output.
local degradedNS, degradedMocks
local function degraded()
  if not degradedNS then
    degradedNS, degradedMocks = dofile("tests/degraded_env.lua")()
    local cf = degradedMocks.DEFAULT_CHAT_FRAME
    local old = rawget(cf, "AddMessage")
    cf.AddMessage = function() end
    degradedNS.Print("burn the banner")
    cf.AddMessage = old
  end
  return degradedNS, degradedMocks
end



-- Drive one line through `env` with every top-level handler replaced by a recorder; describe the
-- verb reached and the rest handed over.
local function routed(env, envMocks, line)
  local saved, ran, gotRest = {}, nil, nil
  for i, entry in ipairs(env.COMMANDS) do
    saved[i] = entry[3]
    entry[3] = function(rest) ran, gotRest = entry[1], rest end
  end
  local cf  = envMocks.DEFAULT_CHAT_FRAME
  local old = rawget(cf, "AddMessage")
  cf.AddMessage = function() end
  local ok, err = pcall(function() env.Slash:OnSlash(line) end)
  cf.AddMessage = old
  for i, entry in ipairs(env.COMMANDS) do entry[3] = saved[i] end
  if not ok then error(err) end
  return ("verb=%s rest=%q"):format(tostring(ran), tostring(gotRest))
end

test("slash verbs: the stub's split agrees with the live dispatcher's over a corpus", function()
  -- The stub dispatcher splits the top verb itself; the live one is the library's. Both must reach
  -- the same handler with the same rest.
  -- red under: any drift of the stub's split (a verb not folded, a rest trimmed or re-cased).
  local NS2, mocks2 = degraded()
  for _, line in ipairs({ "DEBUG events", "  profile   Raid Night", "Toggle TARGET", "debug HOLD 5 2",
      "x" }) do
    assertEqual(routed(NS2, mocks2, line), routed(NS, T.mocks, line),
      ("degraded and live route %q alike"):format(line))
  end
end)


-- -- the container and band-set verbs (the v0.1.0 plan, Task 8; design spec 5.7) -----------------

local E = dofile("tests/settings_env.lua")
local function rm(line) return E.capture(function() NS.Slash:OnSlash(line) end) end

test("slash: test_new_unit_arg — /rm new takes a unit, defaults to target, and refuses one it does not watch", function()
  E.with(function()
    local out = rm("new focus")
    local ids = NS.CM.List()
    assertEqual(#ids, 1)
    assertEqual(NS.CM.Get(ids[1]).unit, "focus", "the unit argument is the container's unit")
    local _, selected = NS.SelectedContainer()
    assertEqual(selected, ids[1], "and the new container is selected")
    assertTrue(E.said(out, "Created 'Focus'"), "it says what it made")
    rm("new")
    assertEqual(NS.CM.Get(NS.CM.List()[2]).unit, "target", "a bare /rm new is a target container")
    out = rm("new raid1")
    assertEqual(#NS.CM.List(), 2, "an unknown unit makes nothing")
    assertTrue(E.said(out, "Usage: /rm new"), "and prints the usage line")
  end)
end)

test("slash: test_select_by_name — /rm select takes a number or a name in any case", function()
  E.with(function()
    local a, b = NS.CM.Create("target"), NS.CM.Create("mouseover")
    rm("select mouseOVER")
    local _, selected = NS.SelectedContainer()
    assertEqual(selected, b, "by name, case-insensitively")
    rm("select 1")
    _, selected = NS.SelectedContainer()
    assertEqual(selected, a, "by its number in /rm containers")
    local out = rm("select nobody")
    _, selected = NS.SelectedContainer()
    assertEqual(selected, a, "an unknown name moves nothing")
    assertTrue(E.said(out, "No range display 'nobody'"))
    out = rm("containers")
    assertTrue(E.said(out, "* 1. Target (target, screen)"), "the list marks the selection: " .. table.concat(out, " | "))
    assertTrue(E.said(out, "  2. Mouseover (mouseover, screen)"))
  end)
end)

test("slash: /rm delete takes a number or a name, asks first, and selects the neighbor", function()
  -- red under: a runDelete that deletes at once (the panel's Delete asks; the verb must too).
  E.with(function()
    local shown = E.spyPopups()
    local a, b = NS.CM.Create("target"), NS.CM.Create("focus")
    NS.SelectContainer(a)
    rm("delete target")
    assertTrue(NS.CM.Get(a) ~= nil, "nothing is deleted before the answer")
    assertEqual(#shown, 1, "the verb shows the confirmation")
    assertEqual(shown[1].which, "RANGEMASTER_DELETE_CONTAINER")
    assertEqual(shown[1].a, "Target", "naming the container")
    assertEqual(shown[1].data, a, "the popup carries the id the name resolved to")
    local out = E.capture(function() E.accept(shown[1]) end)
    assertEqual(NS.CM.Get(a), nil, "deleted by name, on Yes")
    assertTrue(E.said(out, "Deleted container 'Target'"))
    local _, selected = NS.SelectedContainer()
    assertEqual(selected, b)
    out = rm("delete 9")
    assertTrue(NS.CM.Get(b) ~= nil, "an unknown number deletes nothing")
    assertTrue(E.said(out, "No range display '9'"))
  end)
end)

test("slash: test_preset_verb — /rm preset confirms, applies, undoes and refuses an unknown key", function()
  E.with(function()
    local shown = E.spyPopups()
    rm("preset expert")
    assertEqual(#NS.CM.List(), 6, "an empty profile applies at once")
    assertEqual(#shown, 0)
    rm("preset simple")
    assertEqual(#shown, 1, "with containers to replace it asks first")
    assertEqual(shown[1].which, "RANGEMASTER_APPLY_PRESET")
    assertEqual(#NS.CM.List(), 6, "and changes nothing before the answer")
    rm("preset undo")
    assertEqual(#NS.CM.List(), 0, "undo puts back the empty profile the first preset replaced")
    local out = rm("preset bogus")
    assertTrue(E.said(out, "Usage: /rm preset [simple|text|numbers|advanced|expert|ka0s|undo]"))
    rm("preset")
    local f = NS.PresetPicker.frame
    assertTrue(f and f:IsShown(), "a bare /rm preset opens the preset picker")
    E.capture(function() NS.HidePresetPicker() end)
  end)
end)

test("slash: /rm bands lists the band sets with the selection marked, and selects one", function()
  E.with(function()
    local ids = NS.BandSets.List()
    local out = rm("bands")
    assertTrue(E.said(out, "* 1. " .. NS.BandSets.Get(ids[1]).name), "the default set is marked: " .. table.concat(out, " | "))
    -- Red under a /rm bands that drops the selected set's band ribbon (plan 2026-11-19 M8 keeps it:
    -- command output, not a settings preview), or under NS.BandRibbon removed.
    assertEqual(type(NS.BandRibbon), "function", "the band ribbon still has its one caller")
    local ribbon = NS.BandRibbon((NS.SelectedBandSet())):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    assertTrue(E.said(out, ribbon), "the selected set's ribbon is printed: " .. table.concat(out, " | "))
    rm("bands 2")
    local _, selected = NS.SelectedBandSet()
    assertEqual(selected, ids[2])
    out = rm("bands nothing")
    assertTrue(E.said(out, "No band set 'nothing'"))
  end)
end)

test("slash: a name two band sets or containers share is ambiguous, and selects neither", function()
  E.with(function(p)
    local ids = NS.BandSets.List()
    -- A hand-edited SavedVariables file is the one way two names can still meet: every writer suffixes.
    p.bandSets[ids[2]].name, p.bandSets[ids[3]].name = "Twin", "twin"
    NS.SelectBandSet(ids[1])
    local out = rm("bands Twin")
    local _, selected = NS.SelectedBandSet()
    assertEqual(selected, ids[1], "the selection did not move")
    assertTrue(E.said(out, "More than one band set is named 'Twin'"), "and the ambiguity is said: " .. table.concat(out, " | "))
    rm("bands 3")
    _, selected = NS.SelectedBandSet()
    assertEqual(selected, ids[3], "its number still selects it")
    local a, b = NS.CM.Create("target"), NS.CM.Create("focus")
    p.containers[b].name = "target"
    NS.SelectContainer(b)
    out = rm("select Target")
    local _, sel = NS.SelectedContainer()
    assertEqual(sel, b, "an ambiguous container name moves nothing")
    assertTrue(a ~= b and E.said(out, "More than one range display is named 'Target'"), table.concat(out, " | "))
  end)
end)

test("slash: /rm pick starts the frame picker for the selected container, whose pick attaches it", function()
  E.with(function()
    local id = NS.CM.Create("target")
    local saved = NS.FramePicker.Start
    local onPick
    NS.FramePicker.Start = function(fn) onPick = fn; return true end
    local ok, err = pcall(function()
      rm("pick")
      assertTrue(onPick ~= nil, "the picker started")
      E.capture(function() onPick("PlayerFrame") end)
      local a = NS.CM.Get(id).anchor
      assertEqual(a.mode, "frame")
      assertEqual(a.frame.provider, "custom")
      assertEqual(a.frame.name, "PlayerFrame")
    end)
    NS.FramePicker.Start = saved
    if not ok then error(err, 0) end
  end)
end)
