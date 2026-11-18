local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- The type-aware parser is LibKa0s-Slash-1.0's now (`lib.ParseValue`), and its cases live in that
-- repo's tests/test_slash.lua — the bool vocabulary, the clamp, the case-sensitive enum, the
-- 0-255 color rescale and the unknown-type message. Keeping copies here would be two places to
-- fix one bug, which is what testing-§8 forbids.

test("FormatSchemaValue formats by type", function()
  assertEqual(NS.FormatSchemaValue({ type = "bool" }, true), "true")
  assertEqual(NS.FormatSchemaValue({ type = "bool" }, false), "false")
  assertEqual(NS.FormatSchemaValue({ type = "number", fmt = "%d px" }, 200), "200 px")
  assertEqual(NS.FormatSchemaValue({ type = "number" }, 3), "3")
  assertEqual(NS.FormatSchemaValue({ type = "color" }, { r = 1, g = 0, b = 0, a = 1 }),
    "{1.00, 0.00, 0.00, 1.00}")
end)

test("ValidateSchema resolves every real path against defaults (0 errors, 0 missing)", function()
  local errors, resolved, missing = NS.ValidateSchema()
  assertEqual(errors, 0)
  assertEqual(missing, 0)
  assertTrue(resolved > 0, "at least one path should resolve")
end)

test("ValidateSchema reports a planted path that does not resolve against defaults", function()
  local bogus = { path = "doesNotExist", page = "appearance", type = "number", label = "x" }
  NS.Schema[#NS.Schema + 1] = bogus
  local _, _, missing = NS.ValidateSchema()
  assertEqual(missing, 1)
  NS.Schema[#NS.Schema] = nil  -- remove the planted row
end)

test("ValidateSchema flags an invalid page/type as a shape error", function()
  local bad = { path = "barWidth", page = "nope", type = "weird", label = "x" }
  NS.Schema[#NS.Schema + 1] = bad
  local errors = NS.ValidateSchema()
  assertTrue(errors >= 2, "invalid page + invalid type should be two errors")
  NS.Schema[#NS.Schema] = nil
end)

test("ValidateSchema prints through NS.Print, resolved at call time, with no hand-typed tag", function()
  -- R-08: the chat tag comes from the single NS.PREFIX that NS.Print stamps (slash-commands-§4).
  -- red under: a DEFAULT_CHAT_FRAME write with its own "[RM]" literal, or a load-time capture of
  -- NS.Print that this spy cannot reach.
  local bad = { path = "barWidth", page = "nope", type = "weird", label = "x" }
  local lines, orig = {}, NS.Print
  NS.Print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
  NS.Schema[#NS.Schema + 1] = bad
  local ok, err = pcall(NS.ValidateSchema)
  NS.Schema[#NS.Schema] = nil
  NS.Print = orig
  assertTrue(ok, tostring(err))
  assertTrue(#lines > 0, "the shape errors reached chat through NS.Print")
  local src = io.open("settings/Schema.lua", "r")
  assertTrue(src ~= nil, "cannot open settings/Schema.lua (tests run from the repo root)")
  local body = src:read("*a")
  src:close()
  assertEqual(body:find("[RM]", 1, true), nil, "no second copy of the chat tag in settings/Schema.lua")
  assertEqual(body:find("DEFAULT_CHAT_FRAME", 1, true), nil, "no direct chat-frame write")
end)

-- ── Schema integrity ───────────────────────────────────────────────────────────────
--
-- ValidateSchema above is the runtime guard the addon ships with (it only PRINTS, and only checks
-- page/type/path). These are the stricter build-time invariants: they hold for the schema as it
-- stands today, so a new row that forgets a tooltip, a slider range, or a default fails here
-- rather than shipping a half-wired option.

test("every schema row carries a label and a tooltip description", function()
  -- `tooltip` OR `desc`, because the flow engine reads exactly that: `row.tooltip or row.desc`
  -- (libs/LibKa0s/OptionsWidgets.lua's tooltipBody). `desc` is this addon's older spelling and the
  -- one its hand-written rows still use; `tooltip` is what the composers emit and what the rest of
  -- the collection declares. Asserting only `desc` would fail every composed row while the tooltip
  -- it names renders perfectly, which is a test measuring a spelling rather than a behavior.
  -- red under: dropping the tooltip from any composed block, or the desc from a hand-written row.
  for i, row in ipairs(NS.Schema) do
    local where = "row #" .. i .. " (" .. tostring(row.path) .. ")"
    local body = row.tooltip or row.desc
    assertTrue(type(row.label) == "string" and row.label ~= "", where .. " needs a label")
    assertTrue(type(body) == "string" and body ~= "", where .. " needs a tooltip or desc")
  end
end)

test("every schema path is unique", function()
  -- FindSchemaRow returns the FIRST match, so a duplicate path silently shadows the later row:
  -- its widget writes the setting but /rm get/set and the Defaults button read the other one.
  local seen = {}
  for _, row in ipairs(NS.Schema) do
    assertEqual(seen[row.path], nil, "duplicate schema path: " .. tostring(row.path))
    seen[row.path] = true
  end
end)

test("every schema row declares a default", function()
  -- ApplyDefault bails out on a nil default, so a row without one is silently skipped by
  -- /rm reset, /rm resetall and the per-panel Defaults button.
  --
  -- A `sessionOnly` row is exempt, and is the only thing that is: its value is not in the profile
  -- at all (core/Data.lua's session-settings registry answers it), so there is nothing for a reset
  -- to restore it TO. Giving the debug-console toggle a default would make "reset all settings"
  -- close a console window the player opened, which is not a setting.
  -- red under: adding a default to the console row, or dropping one from any stored row.
  for _, row in ipairs(NS.Schema) do
    if not row.sessionOnly then
      assertTrue(row.default ~= nil, tostring(row.path) .. " has no default to reset to")
    end
  end
end)

test("every row's default matches the value in defaults.profile", function()
  -- Two sources for one value: the schema row drives /rm reset, defaults.profile drives a fresh
  -- profile and the RunMigrations backfill. If they disagree, resetting a setting lands somewhere
  -- other than where a brand-new profile starts.
  --
  -- A `sessionOnly` row is skipped: it has no profile value at all, so defaults.profile has nothing
  -- to agree with. Its `default` (the console's `false`) is only the value a reset writes back
  -- through its session set().
  --
  -- The minimap button is skipped for a DIFFERENT reason, not that one: its value is genuinely
  -- stored, but in the GLOBAL store and in LibDBIcon's own INVERTED spelling, so defaults.profile
  -- has nothing to say about it and defaults.global disagrees with the row on purpose (`hide =
  -- false` is `Minimap button = true`). tests/test_launcher.lua pins that pair head-on, which is
  -- where a reader should look for it.
  --
  -- A selection-relative row (`container.<field>`, `bandSet.<field>`; settings/Schema.lua) means a
  -- field of a registry member, so its one other source is that registry's TEMPLATE, which a new
  -- container or band set is deep-copied from. A field the template leaves nil (a band-set
  -- reference) agrees through the row's declared `nilAs`.
  local defaults = NS.defaults.profile
  local TEMPLATES = { container = NS.CONTAINER_TEMPLATE, bandSet = NS.BANDSET_TEMPLATE }
  local function expected(row)
    local prefix, field = row.path:match("^(%a+)%.(.+)$")
    local template = prefix and TEMPLATES[prefix]
    if not template then return NS.ResolvePath(defaults, row.path) end
    local v = NS.ResolvePath(template, field)
    if v == nil then return row.nilAs end
    -- A stored array the row reads and takes as comma-separated names (`listAsText`, the element
    -- order in settings/Containers_Display.lua) agrees as that text.
    if row.listAsText and type(v) == "table" then return table.concat(v, ",") end
    return v
  end
  for _, row in ipairs(NS.Schema) do
    local skip = row.sessionOnly or row.path == NS.Constants.MINIMAP_PATH
    local want = expected(row)
    if type(row.default) == "table" and not skip then
      assertEqual(type(want), "table", row.path .. " default should be a table in both places")
      for k, v in pairs(row.default) do
        assertEqual(want[k], v, row.path .. "." .. tostring(k) .. " disagrees")
      end
    elseif not skip then
      assertEqual(row.default, want, row.path .. " default disagrees with defaults.profile")
    end
  end
end)

test("every persisted profile default is reachable from a schema row", function()
  -- The other direction: a default with no row is a setting the user can neither see in the panel
  -- nor reach via /rm set. The skin choice lives one level deep, at profile.skin.<key>, so that one
  -- level is walked explicitly. `schemaVersion` is exempt should a profile ever carry one: it is
  -- migration bookkeeping, not a user-facing setting.
  local EXEMPT = { schemaVersion = true }
  local paths = {}
  for _, row in ipairs(NS.Schema) do paths[row.path] = true end
  for key, val in pairs(NS.defaults.profile) do
    -- 542 by name, not a bare `-- luacheck: ignore`: bare silences EVERY code on the line,
    -- so a genuine finding here would go quiet too. The empty branch is the point -- an
    -- exempt key is asserted about in neither direction -- and spelling it as a first arm
    -- keeps the three cases (exempt / skin / flat) readable as one list.
    if EXEMPT[key] then -- luacheck: ignore 542
      -- bookkeeping, not a setting
    elseif key == "skin" then
      -- The skin choice, one level deep: profile.skin.<field>.
      for field in pairs(val) do
        local path = "skin." .. field
        assertTrue(paths[path], "profile default '" .. path .. "' has no schema row")
      end
    else
      assertTrue(paths[key], "profile default '" .. key .. "' has no schema row")
    end
  end
end)

test("every number row declares a usable min/max range", function()
  for _, row in ipairs(NS.Schema) do
    if row.type == "number" then
      assertEqual(type(row.min), "number", row.path .. " needs a min for its slider and clamp")
      assertEqual(type(row.max), "number", row.path .. " needs a max")
      assertTrue(row.min < row.max, row.path .. " has an inverted range")
      assertTrue(row.default >= row.min and row.default <= row.max,
        row.path .. " default sits outside its own range")
    end
  end
end)

test("every string row supplies a values source", function()
  -- parseString validates against allowedValues(row). A free-text row (dialogControl = "EditBox")
  -- is the one exception: LibKa0s-Slash's parser leaves it unconstrained (SlashParse minor 10), so
  -- `/rm set` takes any value; the Skin tab's Font and Texture overrides are two, because a
  -- media pack may register its keys after the schema loads.
  for _, row in ipairs(NS.Schema) do
    if row.type == "string" and row.dialogControl ~= "EditBox" then
      local t = type(row.values)
      assertTrue(t == "function" or t == "table", row.path .. " needs values for its dropdown")
    end
  end
end)

-- ── the options-ui v2 adoption invariants ──────────────────────────────────────────
--
-- Three loops over the whole schema, each pinning one rule the library now depends on. They are
-- deliberately whole-schema rather than per-page: a rule that holds on the pages someone remembered
-- to list is a rule that stops holding the day a page is added.

test("every row on every page carries a `group`", function()
  -- options-ui-§13: a page whose rows declare no group cannot draw a strip. The library reports it
  -- and renders the page untabbed, which is a silent downgrade -- the page simply looks unlike
  -- every other page in the collection and nothing in a suite notices.
  --
  -- `skipRender` rows are exempt and are the only exemption: their widget is drawn by something
  -- other than the flow engine (the Skin tab's rows, drawn by the library's AppearanceTab). They
  -- still carry a group naming their subject, so this is an exemption from being COUNTED, not from
  -- being attributable.
  -- red under: deleting `group` from any row, on any page.
  for i, row in ipairs(NS.Schema) do
    local where = "row #" .. i .. " (" .. tostring(row.path) .. ")"
    assertTrue(type(row.group) == "string" and row.group ~= "",
      where .. " carries no group, so it belongs to no tab")
  end
end)

test("no color row carries `disabledIf`, and every pair declares whose class it means", function()
  -- Two halves of options-ui-§17, in one walk because they are the same rule from two sides.
  --
  -- `disabledIf` on a color row is anti-pattern #74: the swatch is still read for its ALPHA under
  -- class color, so graying it tells the player something untrue. The tooltip says it in words
  -- instead (H.CLASS_COLOR_NOTE).
  --
  -- `classColorSource` is DECLARED because the path cannot be trusted to say it: a row stored
  -- under `units.<unit>.` that drew the player's own spells would be player-scoped. On this addon
  -- every one of the four surfaces paints the tracked unit's own bar, so every pair is "unit" --
  -- and that declaration is what an audit reads.
  -- red under: a `disabledIf` coming back, or a pair silently reverting to the player's class.
  --
  -- A PALETTE swatch (`paletteSwatch`) is options-ui-§17's one exemption: a color that identifies
  -- something other than a player -- the band set's unknown gray -- has no class to take, so it has
  -- no companion and declares no source. It still may never gray itself out.
  for _, row in ipairs(NS.Schema) do
    if row.type == "color" and row.paletteSwatch then
      assertEqual(row.disabledIf, nil, row.path .. " must never gray itself out")
    elseif row.type == "color" then
      assertEqual(row.disabledIf, nil, row.path .. " must never gray itself out")
      assertEqual(row.classColorSource, "unit", row.path .. " does not declare whose class it means")
      assertEqual(row.classColorUnit, row.unit, row.path .. " names a unit other than its own")
    end
  end
  -- The companion carries the same declaration, so an audit reading either row gets one answer.
  for i, row in ipairs(NS.Schema) do
    if row.type == "color" and not row.paletteSwatch then
      local companion = NS.Schema[i + 1]
      assertEqual(companion.classColorSource, row.classColorSource,
        row.path .. " and its companion disagree about whose class")
      assertEqual(companion.classColorUnit, row.classColorUnit)
      assertEqual(companion.disabledIf, nil)
    end
  end
end)

test("`disabledIf` names a real sibling setting", function()
  -- A typo'd disabledIf reads nil, which is falsey, so the widget would simply never gray out —
  -- a silent failure with no error to notice. The bar family's is a predicate of the row, as the
  -- engine takes it (OptionsCompose minor 18), and has no path to resolve.
  for _, row in ipairs(NS.Schema) do
    if type(row.disabledIf) == "function" then
      assertEqual(type(row.disabledIf(row)), "boolean", row.path)
    elseif row.disabledIf then
      assertTrue(NS.ResolvePath(NS.defaults.profile, row.disabledIf) ~= nil,
        row.path .. " disabledIf='" .. row.disabledIf .. "' does not resolve")
    end
  end
end)

test("every schema row lands on a page the panel actually builds", function()
  local pages = { general = true, appearance = true, profiles = true, bandsets = true, containers = true,
    containers_display = true, containers_indicator = true, containers_visibility = true,
    containers_sounds = true }
  for _, row in ipairs(NS.Schema) do
    assertTrue(pages[row.page], tostring(row.path) .. " is on unknown page " .. tostring(row.page))
  end
end)

-- ── SetByPath / ApplyDefault dispatch ──────────────────────────────────────────────

test("the schema runtime is LibKa0s-Schema-1.0's, over the live schema array", function()
  -- The live build must be on the library: a stub answering here would keep every case in this file
  -- green while the [Set] line, the bracket's count and the validator went silent.
  local lib = T.mocks.LibStub("LibKa0s-Schema-1.0", true)
  assertTrue(lib ~= nil, "the vendored Schema major registered in this build")
  assertTrue(NS.__schemaLib == lib, "settings/Schema.lua resolved the library, not its stub")
  assertTrue(NS.SchemaRuntime.AllRows() == NS.Schema, "the runtime holds the schema array itself")
  assertTrue(NS.SetByPath == NS.SchemaRuntime.Set, "the host's seam name is the instance's Set")
  assertTrue(NS.FindSchemaRow == NS.SchemaRuntime.FindRow, "and its lookup the instance's FindRow")
end)

test("the minimap row survives a sweep, and a named reset still resets it", function()
  -- launcher-§3 through the runtime's resetExempt, which binds only while a bracket is open. It
  -- replaced a wrapper on the Options descriptor's applyDefault, which a reset through the
  -- instance's own ApplyDefault would have bypassed.
  local path = NS.Constants.MINIMAP_PATH
  local row = NS.FindSchemaRow(path)
  NS.SetByPath(path, false)
  NS.Bulk.Run("reset", "probe", function() NS.ApplyDefault(row) end)
  assertEqual(NS.GetSetting(path), false, "a sweep left the hidden button hidden")
  NS.ApplyDefault(row)
  assertEqual(NS.GetSetting(path), true, "a reset that names the row brings the button back")
end)

test("SetByPath refuses a path with no schema row, and stores nothing", function()
  -- A behavior change taken on purpose with LibKa0s-Schema-1.0 (its adoption notes, JC-2):
  -- architecture-§5 scopes the seam to schema-row paths, so an unknown path is refused rather than
  -- stored. It used to round-trip, because the write happened before the row lookup; nothing in the
  -- addon relied on that, and a typo'd path now says so instead of writing a key nobody reads.
  local ok, why = NS.SetByPath("someInternalKey", 7)
  assertEqual(ok, false, "the write is refused")
  assertTrue(type(why) == "string" and why:find("someInternalKey", 1, true) ~= nil,
    "and the reason names the path: " .. tostring(why))
  assertEqual(NS.db.profile.someInternalKey, nil, "nothing was stored")
end)

test("ResolvePath walks a dotted path", function()
  local t = { units = { target = { barWidth = 275 } } }
  assertEqual(NS.ResolvePath(t, "units.target.barWidth"), 275)
end)

test("ResolvePath returns nil for a missing branch instead of raising", function()
  local t = { units = {} }
  assertEqual(NS.ResolvePath(t, "units.focus.barWidth"), nil)
  assertEqual(NS.ResolvePath(t, "nope.at.all"), nil)
end)

test("ResolvePath still handles a flat key", function()
  assertEqual(NS.ResolvePath({ hidden = true }, "hidden"), true)
end)

test("SetPath writes through a dotted path and creates intermediate tables", function()
  local t = {}
  NS.SetPath(t, "units.focus.barWidth", 321)
  assertEqual(t.units.focus.barWidth, 321)
end)

test("ValidateSchema resolves nested paths against defaults.profile", function()
  local errors, resolved, missing = NS.ValidateSchema()
  assertEqual(errors, 0, "no malformed schema rows")
  assertEqual(missing, 0, "every schema path must resolve against the defaults profile")
  assertTrue(resolved > 0)
end)

test("each unit's row set for a page is the same size", function()
  for _, page in ipairs({ "appearance" }) do
    local n = #NS.SchemaForPage(page, "target")
    assertEqual(#NS.SchemaForPage(page, "focus"), n,
      page .. ": target and focus must expose identical settings")
  end
end)

-- ── FormatSchemaValue's library seam ───────────────────────────────────────────────
--
-- The formatter itself is LibKa0s-Slash-1.0's and is covered in that repo. What this addon owns is
-- the seam: the major is resolved once at file load (library-stack-§4 — settings/Schema.lua loads
-- long after libs\LibKa0s\LibKa0s.xml, so the answer can never change later), and the branch taken
-- when that resolution came back empty.

test("FormatSchemaValue resolves the Slash major at load, never per call", function()
  local savedLibStub = T.mocks.LibStub
  local calls = 0
  T.mocks.LibStub = setmetatable({}, {
    __call = function(_, name, silent)
      calls = calls + 1
      return savedLibStub(name, silent)
    end,
  })
  local ok, err = pcall(function()
    NS.FormatSchemaValue({ type = "bool" }, true)
    NS.FormatSchemaValue({ type = "color" }, { r = 1, g = 0, b = 0, a = 1 })
  end)
  T.mocks.LibStub = savedLibStub
  if not ok then error(err) end
  assertEqual(calls, 0)
end)

test("a build without LibKa0s-Slash-1.0 falls back to a minimal FormatSchemaValue", function()
  -- Re-load settings/Schema.lua into a scratch namespace with the Slash major absent, which is the
  -- only way to reach the fallback now that the lookup happens once at load. The fallback is
  -- deliberately minimal: its sole caller is the debug-gated [Set] line, inert in that build.
  local Loader = dofile("tests/_kit/loader.lua")
  Loader.addonName = "RangeMaster"
  local savedLibStub = T.mocks.LibStub
  local mocks = setmetatable({
    LibStub = setmetatable({}, {
      __call = function(_, name, silent)
        if name == "LibKa0s-Slash-1.0" then return nil end
        return savedLibStub(name, silent)
      end,
    }),
  }, { __index = T.mocks })
  -- Constants is the one namespace member the file reads at load (the minimap row's sweep
  -- exemption); core/Constants.lua loads long before it in the TOC.
  local NS2 = { Constants = NS.Constants }
  Loader.load("settings/Schema.lua", NS2, mocks)
  assertEqual(NS2.FormatSchemaValue({ type = "bool" }, nil), "nil")
  assertEqual(NS2.FormatSchemaValue({ type = "bool" }, true), "true")
  assertEqual(NS2.FormatSchemaValue({ type = "number", fmt = "%d px" }, 200), "200")
end)

-- the degradation stub, Schema minor 2
--
-- settings/Schema.lua's HostSchemaStub is the instance a library-less load writes through, and it
-- keeps pace with LibKa0s-Schema-1.0 minor 2 (LibKa0s docs/api/Schema/version-2-docs.md, "The
-- degradation stub"): SetMany's all-or-nothing batch, row.normalize, the instance id reaching a
-- row's own get and ApplyDefault, and the writeThrough store for row-less paths the host names.
-- Each case builds its own instance over a local store, so nothing touches the shared suite's db.

local loadDegraded = dofile("tests/degraded_env.lua")
local stubLib = loadDegraded().__schemaLib

local function stubFixture(extra)
  local store, calls = {}, { onChange = {}, announce = {}, batches = {} }
  local rows = {
    { path = "width", default = 100,
      onChange = function(v) calls.onChange[#calls.onChange + 1] = "width=" .. tostring(v) end },
    { path = "height", default = 20,
      validate = function(v) return type(v) == "number", "not a number" end,
      onChange = function(v) calls.onChange[#calls.onChange + 1] = "height=" .. tostring(v) end },
  }
  local d = {
    rows = rows,
    resolveRoot = function() return store, 1 end,
    announce = function(row, path, value)
      calls.announce[#calls.announce + 1] = { row = row, path = path, value = value }
    end,
    writeThrough = { "enabled" },
  }
  for k, v in pairs(extra or {}) do d[k] = v end
  return stubLib:New(d), store, calls, rows
end

test("degraded Schema stub: SetMany refuses the whole batch on one invalid entry", function()
  -- red under: committing inside phase 1 (entry 1 would already be in the store)
  local S, store, calls = stubFixture()
  local ok, err, why, index = S.SetMany({
    { path = "width", value = 150 },
    { path = "height", value = "tall" },
  })
  assertEqual(ok, false)
  assertTrue(type(err) == "string" and err:find("invalid", 1, true) ~= nil, "err: " .. tostring(err))
  assertEqual(why, "not a number")
  assertEqual(index, 2)
  assertEqual(store.width, nil, "entry 1 must not be stored when entry 2 is refused")
  assertEqual(#calls.onChange, 0)
  assertEqual(#calls.announce, 0)
end)

test("degraded Schema stub: SetMany refuses an unknown path with its index", function()
  local S, store = stubFixture()
  local ok, _, _, index = S.SetMany({ { path = "width", value = 1 }, { path = "nope", value = 2 } })
  assertEqual(ok, false)
  assertEqual(index, 2)
  assertEqual(store.width, nil)
end)

test("degraded Schema stub: a valid SetMany stores both, reacts once each, announces per write",
  function()
  local S, store, calls = stubFixture()
  assertEqual(S.SetMany({ { path = "width", value = 150 }, { path = "height", value = 30 } }), true)
  assertEqual(store.width, 150)
  assertEqual(store.height, 30)
  assertEqual(table.concat(calls.onChange, ","), "width=150,height=30")
  assertEqual(#calls.announce, 2)
  assertEqual(calls.announce[1].path, "width")
  assertEqual(calls.announce[2].path, "height")
end)

test("degraded Schema stub: SetMany announces once through announceBatch when given", function()
  local batches = {}
  local S, store, calls = stubFixture({
    announceBatch = function(writes, rid) batches[#batches + 1] = { writes = writes, rid = rid } end,
  })
  assertEqual(S.SetMany({ { path = "width", value = 1 }, { path = "enabled", value = false } },
    { instanceId = 7 }), true)
  assertEqual(#batches, 1)
  assertEqual(#batches[1].writes, 2)
  assertEqual(batches[1].rid, 7)
  assertEqual(batches[1].writes[2].row.writeThrough, true)
  assertEqual(#calls.announce, 0, "announceBatch replaces the per-write announce")
  assertEqual(store.enabled, false)
end)

test("degraded Schema stub: a writeThrough path with no row stores raw and announces a synthetic row",
  function()
  -- red under: dropping the through lookup (the write would be refused as an unknown path)
  local S, store, calls = stubFixture()
  assertEqual(S.Set("enabled", false), true)
  assertEqual(store.enabled, false)
  assertEqual(#calls.onChange, 0, "a written-through path runs no onChange")
  assertEqual(#calls.announce, 1)
  assertEqual(calls.announce[1].row.writeThrough, true)
  assertEqual(calls.announce[1].row.path, "enabled")
  assertEqual(S.FindRow("enabled"), nil, "FindRow answers only real rows")
  S.Set("enabled", true)
  assertTrue(calls.announce[2].row == calls.announce[1].row, "the synthetic row is built once")
end)

test("degraded Schema stub: a row-less path outside writeThrough is still refused", function()
  local S, store, calls = stubFixture()
  local ok, err = S.Set("nope", 1)
  assertEqual(ok, false)
  assertTrue(type(err) == "string" and err:find("no setting", 1, true) ~= nil, tostring(err))
  assertEqual(store.nope, nil)
  assertEqual(#calls.announce, 0)
end)

test("degraded Schema stub: row.normalize's answer is stored, and a nil answer refuses", function()
  local S, store, calls, rows = stubFixture()
  rows[1].normalize = function(v) if v < 0 then return nil, "negative" end return math.floor(v) end
  assertEqual(S.Set("width", 12.7), true)
  assertEqual(store.width, 12)
  assertEqual(calls.onChange[1], "width=12", "onChange receives the normalized value")
  local ok, err, why = S.Set("width", -1)
  assertEqual(ok, false)
  assertTrue(err:find("invalid", 1, true) ~= nil, err)
  assertEqual(why, "negative")
  assertEqual(store.width, 12)
end)

test("degraded Schema stub: Get forwards the instance id to a row's own get", function()
  local S, _, _, rows = stubFixture()
  local seen
  rows[#rows + 1] = { path = "session", get = function(id) seen = id; return "v" end,
    set = function() end }
  assertEqual(S.Get("session", 42), "v")
  assertEqual(seen, 42)
end)

test("degraded Schema stub: ApplyDefault forwards the instance id to Set", function()
  local S, _, _, rows = stubFixture()
  local seen
  rows[1].onChange = function(_, rid) seen = rid end
  assertEqual(S.ApplyDefault(rows[1], 9), true)
  assertEqual(seen, 9)
end)
