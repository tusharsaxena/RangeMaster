local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- settings/OptionsSetup.lua as a FILE: the descriptor's half of the reset contract, and the
-- degradation stub. The panel toolkit itself is LibKa0s-Options-1.0 and is tested in that repo;
-- tests/test_realpages.lua covers this addon's pages drawn through it. What lives here is the one thing that file owns twice over — "what must a global reset never touch" —
-- plus the stub's member set, which is a load-order argument and therefore only provable by loading.

local Helpers = NS.Helpers
local loadDegraded = dofile("tests/degraded_env.lua")

-- ── the Profiles reset veto, on both paths ─────────────────────────────────────────
--
-- settings/OptionsSetup.lua's stub is the one degradation stub in this addon that is
-- LOAD-COMPLETING rather than member-answering, and it keeps its own reset loop, because losing the
-- panel is survivable and losing `/rm resetall` is not. That second loop must veto exactly what the
-- live one vetoes: resetting an AceDBOptions-supplied row deletes user data.

-- Which schema rows a build's "reset everything" leaves alone, as sorted paths. ApplyDefault is
-- looked up on the namespace at call time by both paths, so swapping it in observes the veto
-- without writing anything.
--
-- Two probe rows are appended for the duration, because no SHIPPING row is on the profiles page
-- today — that page's controls are AceDBOptions'. The veto exists for the row that gets added
-- there next, so the probe is what makes this case non-vacuous.
local function vetoedByResetAll(ns, restoreAll)
  local n = #ns.Schema
  table.insert(ns.Schema, { page = "profiles", path = "__probe.onProfilesPage", type = "toggle" })
  table.insert(ns.Schema, { page = "general", path = "__probe.onGeneralPage", type = "toggle" })
  -- A SESSION-ONLY row, which is the one kind the walk must still sweep: its storage is its own
  -- set() rather than the db, so a profile reset cannot reach it (options-ui-§12). This addon ships
  -- none today, so the probe is what keeps the rule under test.
  table.insert(ns.Schema, { page = "general", path = "__probe.sessionOnly", type = "toggle",
                            sessionOnly = true, get = function() return false end,
                            set = function() end })

  local touched = {}
  local orig = ns.ApplyDefault
  ns.ApplyDefault = function(row) touched[row.path] = true end
  local ok, err = pcall(restoreAll)
  ns.ApplyDefault = orig

  local vetoed = {}
  for _, row in ipairs(ns.Schema) do
    if not touched[row.path] then vetoed[#vetoed + 1] = row.path end
  end
  for i = #ns.Schema, n + 1, -1 do ns.Schema[i] = nil end
  if not ok then error(err) end
  table.sort(vetoed)
  return table.concat(vetoed, ",")
end

test("the live and degraded builds veto exactly the same rows from Reset All", function()
  -- One rule — enforced in two places: the descriptor's skipRestoreAll, which the library calls, and
  -- the stub's own loop, which runs with no library at all. They must not be able to drift.
  --
  -- The rule has two clauses now (options-ui-§12). A global reset must not touch AceDBOptions-
  -- supplied rows, because that deletes user data; and it must not touch anything else that lives in
  -- the PROFILE either, because the reset IS a profile reset and writing each row's default first
  -- would refresh the panel once per row for values about to be discarded whole. What survives the
  -- veto is the sessionOnly rows, which a profile reset cannot reach.
  -- red under: a predicate that vetoes only the profiles page, or one that vetoes everything.
  --
  -- Compared over the rows BOTH builds carry. The degraded schema is the live one minus the
  -- composed rows (the Options stub's composers are hollow, options-ui-§1; tests/test_perf.lua
  -- pins that gap), so a live-only row has no degraded verdict to compare against.
  local NS2 = loadDegraded()
  local both = {}
  for _, row in ipairs(NS2.Schema) do both[row.path] = true end
  for _, p in ipairs({ "__probe.onProfilesPage", "__probe.onGeneralPage", "__probe.sessionOnly" }) do
    both[p] = true
  end
  local function shared(list)
    local out = {}
    for p in list:gmatch("[^,]+") do if both[p] then out[#out + 1] = p end end
    return table.concat(out, ",")
  end
  local live = vetoedByResetAll(NS, Helpers.RestoreAllDefaults)
  local degraded = vetoedByResetAll(NS2, NS2.Helpers.RestoreAllDefaults)

  assertTrue(live:find("__probe.onProfilesPage", 1, true) ~= nil,
    "the profiles row must be vetoed — resetting it deletes the player's profiles")
  assertTrue(live:find("__probe.onGeneralPage", 1, true) ~= nil,
    "an ordinary profile-backed row must be vetoed; the profile reset covers it")
  assertFalse(live:find("__probe.sessionOnly", 1, true) ~= nil,
    "a sessionOnly row must still be swept — a profile reset cannot reach it")
  assertEqual(degraded, shared(live),
    "the degraded reset vetoes a different row set than the live one")
  T.mocks.__fireTimers()
end)

-- Run one build's Reset All against a probe sessionOnly row -- the one kind of row both walks
-- still reset -- and report what the reset did to it: the stored value and each onChange value.
-- The probe binds its own session storage, so the write never reaches a profile.
--
-- Registered (indexed) through the build's own seam, and carrying its own get/set, which is the shape
-- a sessionOnly row's storage takes since LibKa0s-Schema-1.0; removed and re-indexed afterwards.
local function resetAllProbe(ns, restoreAll)
  local path = "__probe.resetAllSession"
  local store = { value = false }
  local changes = {}
  local n = #ns.Schema
  ns.RegisterSchemaRows({ { page = "general", group = "Probe", path = path, type = "bool",
                            default = true, sessionOnly = true,
                            get = function() return store.value end,
                            set = function(v) store.value = v end,
                            onChange = function(v) changes[#changes + 1] = v end } })
  local ok, err = pcall(restoreAll)
  for i = #ns.Schema, n + 1, -1 do ns.Schema[i] = nil end
  ns.SchemaRuntime.Reindex()
  if not ok then error(err) end
  return store.value, changes
end

test("Reset All resets a sessionOnly row and fires its onChange once, on both builds", function()
  -- Characterization for #30: the live walk reaches the row through the descriptor's applyDefault
  -- (libs/LibKa0s/Options.lua), the degraded stub through its own loop. Both end in
  -- NS.ApplyDefault, and both must write the default and react to it exactly once.
  local NS2 = loadDegraded()
  for label, pair in pairs({ live = { NS, Helpers.RestoreAllDefaults },
                             degraded = { NS2, NS2.Helpers.RestoreAllDefaults } }) do
    local value, changes = resetAllProbe(pair[1], pair[2])
    assertEqual(value, true, label .. ": the sessionOnly row is back at its default")
    assertEqual(#changes, 1, label .. ": one onChange for the reset row")
    assertEqual(changes[1], true, label .. ": and it receives the default")
  end
  T.mocks.__fireTimers()
end)


test("the degraded Reset All with no AceDB writes the session row and logs nothing", function()
  -- The no-AceDB fallback db has no ResetProfile, so no handler runs. RE-PINNED with
  -- LibKa0s-Schema-1.0: the library-absent runtime's bracket is a depth counter and nothing else
  -- (the log-silent stub), so the `[Set] reset all: N rows` line this build used to write is gone.
  -- What a player can observe is pinned instead: the probe session row the walk reset is written.
  local NS2 = loadDegraded()
  local path, store = "__probe.noAceDB", { value = false }
  NS2.RegisterSchemaRows({ { page = "general", group = "Probe", path = path, type = "bool",
                             default = true, sessionOnly = true, onChange = function() end,
                             get = function() return store.value end,
                             set = function(v) store.value = v end } })
  local lines = {}
  NS2.Debug = function(tag, fmt, ...) lines[#lines + 1] = ("[%s] " .. fmt):format(tag, ...) end
  NS2.State.debug, NS2.db = true, { profile = {}, global = {} }
  local ok, err = pcall(NS2.Helpers.RestoreAllDefaults)
  NS2.State.debug, NS2.db = false, nil
  if not ok then error(err, 0) end
  assertEqual(store.value, true, "the session row is back at its default")
  assertEqual(#lines, 0, "and nothing was logged: " .. table.concat(lines, " | "))
end)


-- ── the stub's member set ──────────────────────────────────────────────────────────

test("the degraded stub publishes LSMValues, the one member reached at file load", function()
  -- A page file that calls it inside a schema-row literal aborts on a nil and takes that page's
  -- rows out of the schema.
  local NS2 = loadDegraded()
  assertEqual(type(NS2.Helpers.LSMValues), "function")
  assertEqual(type(NS2.Helpers.LSMValues("statusbar")), "function", "and it returns a values fn")
end)

test("the degraded stub publishes the five composers, hollow", function()
  -- settings/General.lua calls H.MasterControls inside NS.RegisterSchemaRows, at
  -- FILE LOAD, so a nil aborts the file and takes that page's rows out of the schema exactly as a
  -- nil LSMValues does. So each must EXIST -- and each must answer the empty block (options-ui-§1):
  -- the rows a composer emits are the library's, and a host copy of any of them, however little of
  -- the row it reproduces, is anti-pattern #73. The composed paths a host verb still writes reach
  -- the store through settings/Schema.lua's WRITE_THROUGH list instead (the cases above).
  -- red under: a host copy of any composer (anti-pattern #73).
  local NS2 = loadDegraded()
  local spec = { prefix = "units.player.", page = "appearance", group = "Probe",
                 addonName = "Range Master", debugConsolePath = "state.debugConsole" }
  for _, name in ipairs({ "ColorPair", "FontGroup", "BorderGroup", "BarGroup", "MasterControls" }) do
    assertEqual(type(NS2.Helpers[name]), "function", name .. " is reached at file load")
    local rows = NS2.Helpers[name](spec)
    assertEqual(type(rows), "table", name .. " answers a table")
    assertEqual(#rows, 0, name .. " answers the empty block, not a host copy of the library's")
  end
  local _, tail = NS2.Helpers.MasterControls(spec)
  assertEqual(type(tail), "function", "the afterGroup hook is a no-op, not a nil")
end)

test("the degraded stub answers LibKa0s v1.77.0's four members inert", function()
  -- KeybindingsTab, KeybindRows, KEYBINDS_UNCHANGED and StrataTooltip are owed by every Options
  -- stub (the library's v1.77.0 "What a consumer owes"); this addon calls none of them, so each
  -- answers nothing: no tab, no rows, and no host copy of the library's sentences.
  -- red under: a stub that copies the library's text, or a member missing (the parity suite too).
  local NS2 = loadDegraded()
  assertEqual(NS2.Helpers.KeybindingsTab({}), nil, "no Keybindings tab without the library")
  assertEqual(NS2.Helpers.KeybindRows({}, {}), nil, "no rows without the library")
  assertEqual(NS2.Helpers.KEYBINDS_UNCHANGED, "", "an empty sentence, not a copy of the library's")
  assertEqual(NS2.Helpers.StrataTooltip({ "LOW", "DIALOG" }), "", "an empty tooltip, not a copy")
end)

test("the degraded stub answers LibKa0s v1.78.0's and v1.79.0's skin members inert", function()
  -- AppearanceTab and AppearanceRows (v1.78.0, OptionsAppearance minor 1) and SkinPicker and
  -- HideSkinPicker (v1.79.0, OptionsSkinPicker minor 1) are owed by every Options stub (the
  -- library's "What a consumer owes"). Without the library there is no skin to pick: the tab entry
  -- keeps the library's key and draws nothing, the rows and the picker answer nil, the hide is a
  -- no-op.
  -- red under: a member missing (the parity suite too), or a picker that answers a frame.
  local NS2 = loadDegraded()
  local tab = NS2.Helpers.AppearanceTab({})
  assertEqual(type(tab), "table", "an inert tab entry")
  assertEqual(tab.key, "Appearance", "the library's tab key")
  assertEqual(tab.label, "Skin", "the library's tab label")
  assertEqual(type(tab.render), "function", "a render that draws nothing")
  tab.render()
  assertEqual(NS2.Helpers.AppearanceRows({}, {}), nil, "no rows without the library")
  assertEqual(NS2.Helpers.SkinPicker({}), nil, "no picker without the library")
  NS2.Helpers.HideSkinPicker()
end)

test("the degraded stub answers OptionsCompose minor 11's ResetAllTooltip with the tail alone", function()
  -- ResetAllTooltip(tail) is owed by every Options stub from the v1.77.0 settings-layout extension
  -- (the library's "What a consumer owes", OptionsCompose minor 11). Without the library there is no
  -- reset text to read, so the stub answers only what the caller passed: the tail, or nothing.
  -- red under: a missing member, a host copy of the library's reset wording, or a non-string tail leaking.
  local NS2 = loadDegraded()
  assertEqual(NS2.Helpers.ResetAllTooltip(), "", "no tail, no text")
  assertEqual(NS2.Helpers.ResetAllTooltip("Key bindings are not changed."), "Key bindings are not changed.",
    "a string tail comes back alone")
  assertEqual(NS2.Helpers.ResetAllTooltip(42), "", "a non-string tail adds nothing")
end)

test("the degraded stub answers OptionsCompose minor 15's PositionBlock with no rows and an inert hook", function()
  -- O.PositionBlock is owed by every Options stub from LibKa0s v1.84.0 (the library's Options
  -- document, LibKa0s#59). The live one answers `rows, afterSubgroup`, so the stub keeps both shapes.
  -- red under: a missing member, or a stub that hands back rows with no library to draw them.
  local NS2 = loadDegraded()
  local rows, hook = NS2.Helpers.PositionBlock({})
  assertEqual(#rows, 0, "no rows without the library")
  hook()
end)

test("the degraded stub keeps no private copy of the library's layout constants", function()
  -- Measured, not assumed: dropping each of these from the stub and re-running the degraded load
  -- leaves #NS.Schema unchanged, because every reader sits behind an AceGUI the degraded build never
  -- gets. Their values are lib.LAYOUT's, and a host copy of a library value is the copy that goes
  -- stale.
  local NS2 = loadDegraded()
  for _, name in ipairs({
    "ROW_VSPACER", "SECTION_HEADING_H", "BUTTON_PAIR_REL",
    -- The chrome band's three (options-ui-§13/§14), absent for the same reason; the band's
    -- CALLABLE members are in the stub, and tests/test_surface_parity.lua holds them there.
    "CHROME_GAP", "TAB_H", "BANNER_H",
  }) do
    assertEqual(NS2.Helpers[name], nil, name .. " is a copy of lib.LAYOUT with no degraded reader")
  end
end)

test("PARENT_TITLE reaches the library through the descriptor, not the namespace", function()
  -- The brand reaches the library as descriptor.parentTitle. Nothing on NS reads it, so publishing
  -- it there would advertise a seam with no consumer.
  assertEqual(NS.PARENT_TITLE, nil, "NS.PARENT_TITLE is a file-scope local now")
  assertEqual(T.mocks.__mainPanel.name, "Ka0s Range Master",
    "and the brand still reaches the canvas the library registers")
  -- One literal (R-10): the local is the brand constant, not a second spelling of it. red under:
  -- re-typing a literal into PARENT_TITLE, which drifts from C.BRAND on the next rename.
  assertEqual(T.mocks.__mainPanel.name, NS.Constants.BRAND, "the canvas name IS the brand constant")
  local src = io.open("settings/OptionsSetup.lua", "r")
  assertTrue(src ~= nil, "cannot open settings/OptionsSetup.lua (tests run from the repo root)")
  local body = src:read("*a")
  src:close()
  assertEqual(body:match("\n%s*local%s+PARENT_TITLE%s*=%s*([^\r\n]-)%s*\r?\n"), "NS.Constants.BRAND",
    "PARENT_TITLE reads the one brand constant")
end)

-- ── the Profiles page draws ──────────────────────────────────────────────────────

test("the Profiles page SHOWS the container AceConfigDialog fills, even a pooled (hidden) one", function()
  -- AceGUI:Release hides a widget's frame before pooling it, and neither AceGUI:Create nor
  -- AceConfigDialog:Open shows it again. settings/Profiles.lua creates its SimpleGroup on first
  -- show, when AceGUI's pool is rarely empty, so AceConfigDialog could fill a hidden frame and the
  -- page would read as blank under its header. The Create wrap below hands out every SimpleGroup
  -- hidden, which is exactly the pooled case.
  --
  -- A second full environment, because the shared one has no AceDBOptions and its Profiles page
  -- self-skips (tests/test_realpages.lua pins that). The fakes go into the kit's library table
  -- before the addon loads. RangeMasterDB is process-global, so it is parked around InitDB and
  -- the shared suite's database is never touched.
  -- red under: the renderer not calling container.frame:Show().
  local Loader     = dofile("tests/_kit/loader.lua")
  local buildMocks = dofile("tests/wow_mock.lua")
  Loader.addonName = "RangeMaster"
  local mocks2, NS2 = buildMocks(), {}

  local opened = {}
  mocks2.__libs["AceDBOptions-3.0"] = {
    GetOptionsTable = function() return { type = "group", args = {} } end,
  }
  mocks2.__libs["AceConfig-3.0"] = { RegisterOptionsTable = function() end }
  mocks2.__libs["AceConfigDialog-3.0"] = {
    Open = function(_, app, container) opened[#opened + 1] = { app = app, container = container } end,
  }
  local AceGUI = mocks2.LibStub("AceGUI-3.0")
  local create = AceGUI.Create
  AceGUI.Create = function(self, wtype)
    local w = create(self, wtype)
    if wtype == "SimpleGroup" then w.frame:Hide() end
    return w
  end

  Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), NS2, mocks2)
  Loader.loadAll(Loader.tocFiles("RangeMaster.toc"), NS2, mocks2)
  local savedDB = _G.RangeMasterDB
  _G.RangeMasterDB = nil
  local ok, err = pcall(function()
    NS2:InitDB()
    NS2.CreateOptionsPanel()
  end)
  _G.RangeMasterDB = savedDB
  assertTrue(ok, "the second environment failed to build: " .. tostring(err))

  local panel = mocks2.__subcategories["Profiles"]
  assertTrue(panel ~= nil, "with AceDBOptions present the Profiles page registers")
  panel:__fire("OnShow")
  assertEqual(#opened, 1, "the first show opens the AceDBOptions table once")
  assertEqual(opened[1].app, "RangeMaster-Profiles")
  local frame = opened[1].container and opened[1].container.frame
  assertTrue(frame ~= nil, "AceConfigDialog is handed an AceGUI container")
  assertTrue(frame:IsShown(), "the container AceConfigDialog fills is shown")
end)

-- ── the Reset all settings tooltip names Profiles → Reset Profile ──────────────────────────────
--
-- options-ui-§12: the global reset IS a profile reset here (the descriptor supplies resetProfile)
-- and this addon ships a Profiles page, so the button's tooltip SHOULD name the equivalence. The
-- composer is the only writer of that text; it picks the wording from the descriptor
-- (LibKa0s-Options-1.0 minor 18), and `profilesPage = true` is how the host says the page exists.
-- Read the way AttachTooltip shows it: fire the real button's OnEnter with GameTooltip:AddLine spied.

local RESET_ALL_TIP = "Reset the current profile to its defaults \226\128\148 the same thing "
  .. "Profiles -> Reset Profile does. Your other profiles are not affected."

local function findButton(w, text, depth)
  depth = depth or 0
  if type(w) ~= "table" or depth > 8 then return nil end
  if w.text == text and w.callbacks then return w end
  for _, child in ipairs(w.children or {}) do
    local hit = findButton(child, text, depth + 1)
    if hit then return hit end
  end
  return nil
end

test("General's Reset all settings tooltip says it is the same act as Profiles -> Reset Profile", function()
  -- red under: dropping `profilesPage = true` from the descriptor in settings/OptionsSetup.lua.
  local ctx = Helpers.__panelFor("general")
  assertTrue(ctx ~= nil, "the General page is registered")
  ctx.activeTab = Helpers.MASTER_GROUP
  ctx.panel:Show()
  Helpers.RefreshPanel(ctx, true)
  local btn = findButton(ctx.scroll, "Reset all settings")
  assertTrue(btn ~= nil, "the Master controls tab draws a Reset all settings button")
  assertTrue(btn.callbacks.OnEnter ~= nil, "the button carries a tooltip")

  local tip, lines = T.mocks.GameTooltip, {}
  local saved = rawget(tip, "AddLine")
  rawset(tip, "AddLine", function(_, text) lines[#lines + 1] = text end)
  local ok, err = pcall(btn.callbacks.OnEnter)
  rawset(tip, "AddLine", saved)
  assertTrue(ok, tostring(err))
  assertEqual(#lines, 1, "one tooltip body line")
  assertEqual(lines[1], RESET_ALL_TIP)
end)

-- ── the folder name, for the library's help-mark art (LibKa0s#42) ─────────────────
--
-- LibKa0s-Options-1.0 builds the IdList help mark from `descriptor.addonName`: the vendored
-- `info` art lives at Interface\AddOns\<folder>\libs\LibKa0s\media\icons\info, and the folder is the
-- one thing no other descriptor field carries (PARENT_TITLE is the brand, mainPanelName a frame
-- name). Without it the library draws Blizzard's blue disc and says so on a Cfg debug line. This
-- addon has no IdList today, so the field is latent here; it is passed so the first list that grows
-- a help line draws the collection's art, not the client's.

-- The descriptor settings/OptionsSetup.lua actually hands `lib:New`, captured by a spy on a second
-- full load, the way tests/test_debuglog.lua captures the DebugLog one: the call happens once, at
-- file load, long before any case runs.
local function captureOptionsDescriptor()
  local Loader     = dofile("tests/_kit/loader.lua")
  local buildMocks = dofile("tests/wow_mock.lua")
  Loader.addonName = "RangeMaster"
  local mocks2, NS2 = buildMocks(), {}
  Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), NS2, mocks2)

  local lib = mocks2.LibStub("LibKa0s-Options-1.0")
  local realNew, seen = lib.New, nil
  lib.New = function(self, d) seen = d; return realNew(self, d) end
  local ok, err = pcall(Loader.loadAll, Loader.tocFiles("RangeMaster.toc"), NS2, mocks2)
  lib.New = realNew
  if not ok then error(err, 0) end
  return seen
end

test("the Options descriptor tells the library the FOLDER name", function()
  -- Asserted on the table the library received, not on the source text, so a decoy
  -- `d.addonName = addonName` on a table lib:New never sees cannot pass (anti-pattern #64).
  -- red under: dropping `addonName = addonName,` from the descriptor.
  local d = captureOptionsDescriptor()
  assertTrue(type(d) == "table", "settings/OptionsSetup.lua never called lib:New")
  assertEqual(d.addonName, "RangeMaster",
    "the Options descriptor carries no folder name, so a help mark would draw the client glyph")
end)

test("and the Options descriptor takes that name from the first vararg, not a literal", function()
  -- The spy cannot tell the vararg from a quoted "RangeMaster"; a literal is a second place to
  -- edit on a folder rename, and a wrong folder draws the fallback glyph. And `addonName` is the
  -- FOLDER here, not the MasterControls compose spec's display label of the same field name.
  -- red under: keeping `local _, NS = ...`, or typing the name as a literal.
  local f = io.open("settings/OptionsSetup.lua", "r")
  assertTrue(f ~= nil, "cannot open settings/OptionsSetup.lua (tests run from the repo root)")
  local src = f:read("*a")
  f:close()
  local body = src:gsub("%-%-[^\r\n]*", "")
  assertTrue(body:match("^%s*local%s+addonName%s*,%s*NS%s*=%s*%.%.%.") ~= nil,
    "the file must keep its first vararg as `local addonName, NS = ...`")
  local desc = body:match("\nlocal%s+descriptor%s*=%s*(%b{})")
  assertTrue(desc ~= nil, "cannot find the `local descriptor = { ... }` table")
  assertTrue(desc:find("[\r\n]%s*addonName%s*=%s*addonName%s*,") ~= nil,
    "the descriptor must pass `addonName = addonName,`")
  assertTrue(body:find("\"RangeMaster\"", 1, true) == nil,
    "the folder name must come from the vararg, never a literal")
end)

test("the id-list help mark ships: v1.85.0 owes info on every consumer's line", function()
  -- This addon builds no Options id list, but LibKa0s v1.85.0's kit revision 49 gate asks every
  -- consumer to declare `info` (LibKa0s's own docs/releasing.md, Step 8 for v1.85.0). The kit gate holds declared
  -- == shipped, so this case keeps only the one fact it can add: the art opens.
  local art = io.open("libs/LibKa0s/media/icons/info.tga", "rb")
  assertTrue(art ~= nil, "libs/LibKa0s/media/icons/info.tga is missing")
  art:close()
end)
