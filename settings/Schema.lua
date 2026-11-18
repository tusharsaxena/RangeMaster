local _, NS = ...
-- settings/Schema.lua — the schema rows' runtime and the one write seam (architecture-§5).
--
-- Single source of truth for every user-facing setting. Each settings/<page>.lua file populates
-- this array via NS.RegisterSchemaRows({...}); the panel renderer (LibKa0s-Options-1.0:
-- RenderSchema) and the slash dispatcher (/rm list, /rm get, /rm set, /rm reset) both walk it.
--
-- Adding a new option is one schema row — the AceGUI widget on the relevant sub-page and the
-- slash-command surface for that path are wired automatically.
--
-- Schema row shape:
--   {
--     path    = "scale",           -- key in db.profile (also /rm set path); `global.` for db.global
--     page    = "general",         -- which settings/<page>.lua renders it
--     group   = "Master controls", -- the page's TAB this row belongs to (options-ui-§13); tabs are
--                                  -- drawn in the order their first row was registered
--     order   = 10,                -- render order within the group
--     type    = "bool"|"number"|"string"|"color",
--     subgroup = "Size",           -- a heading INSIDE a tab, for a tab that mixes control kinds
--                                  -- (options-ui-§7). A subgroup repeating its tab's own name is
--                                  -- forbidden
--     label   = "Master scale",    -- widget label and /rm list/get display
--     tooltip = "...",             -- tooltip body. `desc` is the older spelling and still read --
--                                  -- the flow engine answers `row.tooltip or row.desc` -- so the
--                                  -- composed rows carry `tooltip` and the hand-written ones `desc`
--     default = 200,               -- used by /rm reset and /rm resetall
--     min, max, step,                                 -- number
--     values        = function() return {...} end,    -- string (select); k=v map
--     dialogControl = "Ka0sMedia_Statusbar",          -- string (LSM swatch dropdown)
--     hasAlpha      = true,                           -- color
--     classColorSource = "unit"|"player",             -- color pair: WHOSE class this surface means
--     classColorUnit   = "target",                    -- ... and which unit, when it is "unit"
--     onChange   = function(v) ... end,               -- the row's reaction; a declared no-op where none
--     fmt        = "%.1f sec",                        -- /rm list/get formatting hint
--     solo       = true,                              -- panel only: render alone in the LEFT HALF
--     startsLine = true,                              -- panel only: flush the pending line first,
--                                                     -- so a declared pair cannot be split
--     sessionOnly = true,                             -- value is NOT in the profile; see
--                                                     -- the row carries its own get / set
--     skipRender  = true,                             -- keep it in the schema; the host draws it
--   }
--
-- NO ROW CARRIES `disabledIf`, and no color row ever may (options-ui-§17, anti-pattern #74): a
-- swatch is still read for its ALPHA while its class-color companion is on, so graying it would
-- tell the player something untrue. The field is the library's and still works; this addon simply
-- does not ask for it.

NS.Schema = NS.Schema or {}

-- ---------------------------------------------------------------------
-- The runtime: LibKa0s-Schema-1.0, or the host's degradation stub
-- ---------------------------------------------------------------------
--
-- This file is the major's setup file. The ROWS are ours: the page files register them, and every
-- path, default, widget and onChange is this addon's. The MACHINERY around them is the library's
-- (libs/LibKa0s/Schema.lua; contract in LibKa0s docs/api/Schema/version-1-docs.md): the dotted-path
-- walkers, the path index, the single write seam (architecture-§5), the bulk bracket
-- (debug-logging-§10), the profile reset's changed-row count, and the load-time shape check. Each
-- of those used to be written out here, and eight sibling addons carried their own copy.
--
-- The public names below are bound to the instance's members: NS.SetByPath, NS.FindSchemaRow, NS.RegisterSchemaRows, NS.ApplyDefault,
-- NS.Bulk, NS.ResolvePath / NS.SetPath, the reset count trio and NS.ValidateSchema.

--- The degradation stub (LibKa0s docs/api/Schema/version-2-docs.md, "The degradation stub"). It
--- keeps pace with the major's minor 2: SetMany (the all-or-nothing batch), row.normalize, the
--- instance id reaching a row's own get and ApplyDefault, and the writeThrough store -- the
--- descriptor's list of row-less paths it stores raw and announces with a synthetic row.
---
--- WRITE-COMPLETING AND LOG-SILENT, and a deliberate, documented duplication. This major is not
--- reached only by the panel and the CLI, which a library-less build has lost anyway: every
--- settings read goes through it, and three HOST writers write through it on the degraded path --
--- the host verbs (settings/Slash.lua), the Options stub's Reset All (settings/OptionsSetup.lua)
--- and the launcher menu (core/LauncherSetup.lua). A stub that refused a write would leave all
--- three dead on exactly the install this exists for (slash-commands-§1, options-ui-§1; anti-pattern
--- #56 shape 2). options-ui-§1 names this shape, the RUNTIME-COMPLETING stub, and ties it to this
--- major alone.
---
--- The host writers that reach COMPOSED rows -- `enabled` and `locked`, which H.MasterControls
--- emits and the Options stub's hollow composers do not -- write through the declared
--- WRITE_THROUGH list below (options-ui-§1 route (a)): stored raw at the path, then announced with
--- the synthetic row, whose announce dispatches the host's own reaction. Every other row-less path
--- is still refused.
---
--- It completes what a player can observe -- reads, writes (one at a time or as a batch), the
--- row's reaction, the announce and the sweep veto -- and not what only feeds the debug console:
--- the [Set] line, the bracket's tally and the reset count. The degraded DebugLog stub
--- (core/DebugLogSetup.lua) discards those lines, so the degraded build has nowhere to show one. It is the reference stub the library's own suite pins
--- against a live instance, whole: tests/test_surface_parity.lua holds it to the same surface.
local function HostSchemaStub()
    local stubLib = {}
    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copy(x) end
        return out
    end
    function stubLib.SplitPath(path)
        local parts = {}
        if path ~= nil then
            for seg in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = seg end
        end
        return parts
    end
    local function partsOf(p) return type(p) == "table" and p or stubLib.SplitPath(p) end
    function stubLib.Read(root, p, first)
        local parts, node = partsOf(p), root
        first = first or 1
        if type(root) ~= "table" or #parts < first then return nil end
        for i = first, #parts do
            if type(node) ~= "table" then return nil end
            node = node[parts[i]]
        end
        return node
    end
    function stubLib.Write(root, p, value, first)
        local parts, node = partsOf(p), root
        first = first or 1
        if type(root) ~= "table" or #parts < first then return end
        for i = first, #parts - 1 do
            if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
            node = node[parts[i]]
        end
        node[parts[#parts]] = value
    end
    function stubLib.SameValue(a, b)
        if a == b then return true end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        for k, v in pairs(a) do if not stubLib.SameValue(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end

    -- Colon-called like every major's constructor (`SchemaLib:New{...}`); the stub needs no self.
    function stubLib.New(_, d)
        local S, depth = {}, 0
        local rows = d.rows
        -- writeThrough (since 2): one synthetic row per listed path, built here once and handed
        -- out by identity. It has no validate, normalize, set or onChange, so the seam below stores
        -- it raw and reacts to nothing; `row.writeThrough` is how the host's announce tells it apart.
        local through = {}
        if type(d.writeThrough) == "table" then
            for _, p in ipairs(d.writeThrough) do
                if type(p) == "string" then through[p] = { path = p, writeThrough = true } end
            end
        end
        local function resolve(parts, id)
            if type(d.resolveRoot) ~= "function" then return nil end
            return d.resolveRoot(parts, id)
        end
        function S.AllRows() return rows end
        function S.FindRow(path)
            if type(path) ~= "string" then return nil end
            for _, row in ipairs(rows) do
                if type(row) == "table" and row.path == path then return row end
            end
        end
        -- The row a write goes through: the real row, else a listed path's synthetic one. A path
        -- with a row always takes the row; FindRow never answers a synthetic row.
        local function writeRow(path)
            local row = S.FindRow(path)
            if row then return row end
            if type(path) == "string" then return through[path] end
        end
        function S.AddRows(list, at)
            if type(list) ~= "table" then return 0 end
            at = type(at) == "number" and math.floor(at) or #rows + 1
            if at > #rows + 1 then at = #rows + 1 elseif at < 1 then at = 1 end
            for i, row in ipairs(list) do table.insert(rows, at + i - 1, row) end
            return #list
        end
        function S.Reindex() end
        function S.Get(path, id)
            local row = S.FindRow(path)
            if row and type(row.get) == "function" then return row.get(id) end
            if type(path) ~= "string" or (row and row.sessionOnly) then return nil end
            local parts = stubLib.SplitPath(path)
            local root, first = resolve(parts, id)
            if type(root) ~= "table" then return nil end
            return stubLib.Read(root, parts, first)
        end
        -- validate, then normalize (since 2): the value to store, or `false, err, why`.
        local function checkValue(row, path, value, rid)
            if type(row.validate) == "function" then
                local ok, why = row.validate(value, rid)
                if not ok then return false, "RangeMaster: invalid value for " .. path, why end
            end
            if type(row.normalize) == "function" then
                local out, why = row.normalize(value, rid)
                if out == nil then return false, "RangeMaster: invalid value for " .. path, why end
                value = out
            end
            return true, value
        end
        -- Everything the seam checks before it stores, shared by Set and SetMany so a batch refuses
        -- on exactly the rules a single write does: resolve, validate, normalize, the missing root.
        -- Answers `true, prep`, or `false, err, why, withWhy` with nothing stored. `withWhy` keeps
        -- the answer count: `false, err, why` for a bad value, `false, err` for a missing root.
        local function prepareWrite(row, path, value, id)
            local stored = type(row.set) ~= "function" and not row.sessionOnly
            local prep = { row = row, path = path, rid = id }
            if stored then
                prep.parts = stubLib.SplitPath(path)
                local r, f, got = resolve(prep.parts, id)
                if type(r) == "table" then prep.root, prep.first = r, f end
                if got ~= nil then prep.rid = got end
            end
            local ok, v, why = checkValue(row, path, value, prep.rid)
            if not ok then return false, v, why, true end
            if stored and not prep.root then
                return false, "RangeMaster: nowhere to store " .. path, nil, false
            end
            prep.value = v
            return true, prep
        end
        -- The store: the row's own set with the value as given, or a COPY written at the path; a
        -- sessionOnly row without a set stores nothing.
        local function store(prep)
            if type(prep.row.set) == "function" then
                prep.row.set(prep.value)
            elseif prep.root then
                stubLib.Write(prep.root, prep.parts, copy(prep.value), prep.first)
            end
        end
        local function react(prep)
            local onChange = prep.row.onChange
            if type(onChange) == "function" then onChange(prep.value, prep.rid) end
        end
        local function commit(prep)
            store(prep)
            react(prep)
        end
        -- The write seam's order without its log and tally: refuse, validate, normalize, store,
        -- react, announce. A listed writeThrough path with no row is not refused (see above).
        function S.Set(path, value, id)
            local row = writeRow(path)
            if not row then return false, "RangeMaster: no setting " .. tostring(path) end
            local ok, prep, why, withWhy = prepareWrite(row, path, value, id)
            if not ok then
                if withWhy then return false, prep, why end
                return false, prep
            end
            commit(prep)
            if type(d.announce) == "function" then d.announce(row, path, prep.value, prep.rid) end
            return true
        end
        -- One batch entry, checked as Set checks it: a prep, or `nil, err, why`.
        local function prepareEntry(entry, id)
            local path = type(entry) == "table" and entry.path or nil
            local row = writeRow(path)
            if not row then return nil, "RangeMaster: no setting " .. tostring(path) end
            local ok, prep, why = prepareWrite(row, path, entry.value, id)
            if not ok then return nil, prep, why end
            return prep
        end
        -- The batch's tail: announceBatch once with `{ row, path, value, rid }` per write and the
        -- first write's id, else announce per write. Nothing for an empty batch.
        local function announceAll(preps)
            if #preps == 0 then return end
            if type(d.announceBatch) == "function" then
                local writes = {}
                for i, p in ipairs(preps) do
                    writes[i] = { row = p.row, path = p.path, value = p.value, rid = p.rid }
                end
                d.announceBatch(writes, preps[1].rid)
                return
            end
            if type(d.announce) ~= "function" then return end
            for _, p in ipairs(preps) do d.announce(p.row, p.path, p.value, p.rid) end
        end
        -- SetMany (since 2), all or nothing and log-silent: every entry prepared first, and the
        -- first refusal answers `false, err, why, index` with nothing stored; then every store,
        -- every onChange, and the announce. `opts.act` is not read -- there is no line to make.
        function S.SetMany(entries, opts)
            if type(entries) ~= "table" then entries = {} end
            local id = type(opts) == "table" and opts.instanceId or nil
            local preps = {}
            for i = 1, #entries do
                local prep, err, why = prepareEntry(entries[i], id)
                if not prep then return false, err, why, i end
                preps[i] = prep
            end
            for _, p in ipairs(preps) do store(p) end
            for _, p in ipairs(preps) do react(p) end
            announceAll(preps)
            return true
        end
        function S.Default(path)
            local row = S.FindRow(path)
            return row and copy(row.default)
        end
        function S.ApplyDefault(row, id)
            if type(row) ~= "table" or type(row.path) ~= "string" or row.default == nil then
                return false
            end
            local exempt = d.resetExempt
            if depth > 0 and type(exempt) == "table" and exempt[row.path] then return false end
            return S.Set(row.path, copy(row.default), id)
        end
        -- The bracket keeps its depth, because the sweep veto above reads it; it counts nothing.
        function S.BulkBegin() depth = depth + 1 end
        function S.BulkEnd() if depth > 0 then depth = depth - 1 end end
        function S.BulkRun(act, scope, fn)
            S.BulkBegin(act, scope)
            local ok, err = pcall(fn, { profileReset = false })
            S.BulkEnd(act, scope)
            if not ok then error(err, 0) end
        end
        function S.BulkAdd() end
        function S.InBulk() return depth > 0 end
        function S.CountOffDefault() return 0 end
        function S.ResetCounted(fn) fn() end
        function S.ConsumeResetCount() return nil end
        function S.Validate()
            if type(d.print) == "function" then
                d.print("LibKa0s-Schema-1.0 is missing, so the schema was not checked")
            end
            return 0, 0, 0
        end
        return S
    end
    return stubLib
end

-- Resolved once, at file load (library-stack-§4): the TOC loads libs\LibKa0s\LibKa0s.xml in the
-- lib block, so the major is registered by now or absent for good.
local SchemaLib = LibStub and LibStub("LibKa0s-Schema-1.0", true) or HostSchemaStub()
-- Suite seam only: tests/test_surface_parity.lua holds the stub to the library's surface by name,
-- which it can only do on a degraded load if the stub is reachable.
NS.__schemaLib = SchemaLib

-- The minimap button's row survives every SWEEP (launcher-§3): a page's Defaults button and Reset
-- all settings leave it alone. The library honors this only while a bracket is open, so a player
-- who names the row (`/rm reset global.minimap.shown`) still gets exactly that row reset.
local MINIMAP_PATH = NS.Constants.MINIMAP_PATH

-- Resolved at call time so the suites can spy on NS.Print. core/CoreSetup.lua defines NS.Print on
-- both arms and loads before this file, so there is no fallback to write: the chat tag is NS.PREFIX,
-- stamped once by the printer (slash-commands-§4).
local function chatPrint(line) NS.Print(line) end

-- The composed paths a HOST writer reaches (options-ui-§1 route (a); LibKa0s-Schema-1.0 minor 2).
-- `enabled` is written by /rm enable and /rm disable; `locked` by /rm lock and /rm unlock, the
-- launcher menu's Locked entry (core/LauncherSetup.lua,
-- which runs the /rm lock and /rm unlock handlers).
-- Both rows are emitted by H.MasterControls, and on a load where that composer is absent -- the
-- Options stub's composers answer {} -- no row declares them. Listed here, a write to either still
-- stores, and the announce below hands it to the host's own reaction. A path with a row always
-- takes the row, so on a full load this list changes nothing. Declared once and handed to the live
-- instance and the stub alike: the set is what this addon's degraded writers reach, not a
-- per-arm choice.
local WRITE_THROUGH = { "enabled", "locked" }

-- The two selection-relative prefixes (the section after the bindings below).
local CONTAINER, BANDSET = "container", "bandSet"

local S = SchemaLib:New({
    -- The live array, never copied: the page files register into it through NS.RegisterSchemaRows.
    rows = NS.Schema,
    writeThrough = WRITE_THROUGH,

    -- Where a STORED row lives. Almost every path is the active profile's; a `global.` path is the
    -- account-wide store. Two rows keep their value somewhere else entirely and carry their own
    -- get/set instead (settings/General.lua stamps them): the console toggle (session state) and
    -- the minimap button (LibDBIcon's inverted key). Before the db exists this answers nil, and a
    -- write is refused rather than lost somewhere nobody reads (NS.GetSetting's read falls back to
    -- the shipped defaults).
    resolveRoot = function(parts)
        local db = NS.db
        if parts[1] == "global" then return db and db.global, 2 end
        -- A SELECTION-RELATIVE path (the section below): read against the selected container or
        -- band set. Every row under either prefix carries its own get and set, which reach the
        -- registry's writer, so only a row-less READ (`/rm get container.anchor`) lands here.
        if parts[1] == CONTAINER then return (NS.SelectedContainer()), 2 end
        if parts[1] == BANDSET then return (NS.SelectedBandSet()), 2 end
        return db and db.profile, 1
    end,

    -- A WRITTEN-THROUGH path (WRITE_THROUGH above): its synthetic row carries no onChange,
    -- because the row that would have carried one was never composed. The reaction is still the
    -- host's -- settings/General.lua publishes its Master-controls handlers as NS.MasterReactions
    -- -- so the enable edge still moves the stand-down latch and an in-combat unlock is still
    -- refused. This dispatches host code by path; it is not a copy of any library row.
    announce = function(row)
        if row.writeThrough then
            local react = NS.MasterReactions and NS.MasterReactions[row.path]
            if react then return react() end
        end
    end,

    -- Looked up at call time, not captured: the debug sink is wired later in the load on some
    -- paths, and the suites spy on NS.Debug.
    debug = function(tag, fmt, ...) NS.Debug(tag, fmt, ...) end,
    -- Asked BEFORE a line is formatted: a ColorPicker drag reaches the seam every frame, and with
    -- debug off it must do no string work at all.
    debugEnabled = function() return NS.State and NS.State.debug end,
    -- The same renderer `/rm get` echoes with (LibKa0s-Slash-1.0), so the two never disagree.
    format = function(row, v) return NS.FormatSchemaValue(row, v) end,
    print = chatPrint,
    -- The minimap row survives every sweep (launcher-§3): General's Defaults walks every row on its
    -- page, and a player's hidden button is not a General setting.
    resetExempt = { [MINIMAP_PATH] = true },
})
NS.SchemaRuntime = S

-- ---------------------------------------------------------------------
-- The host's names, bound to the instance
-- ---------------------------------------------------------------------

--- Append a list of schema rows. Called once per settings/<page>.lua at file-load time.
NS.RegisterSchemaRows = S.AddRows
--- The row at `path`, or nil. First registered wins on a duplicate (ValidateSchema reports one).
NS.FindSchemaRow = S.FindRow

--- Write a value for `path`, then its row's onChange, then the announce. The single write seam for
--- every schema-row path (architecture-§5): /rm set, /rm lock, /rm unlock, /rm toggle and every
--- panel widget call it, and every reset to a row's default reaches it through NS.ApplyDefault. A
--- path with no schema row is REFUSED (`false, reason`) and stores nothing, and a table value is
--- stored as a copy, so the caller's table and the store never alias.
NS.SetByPath = S.Set

--- Reset one row to its default, through the same seam (a deep copy of the default). Used by
--- /rm reset <path>, the per-page Defaults button and Reset All's sessionOnly sweep. A row with no
--- `default` writes nothing; inside a sweep the minimap row writes nothing either.
NS.ApplyDefault = S.ApplyDefault

-- The dotted-path primitives. A nested setting lives at a dotted path (`skin.skin`); a flat key ("locked")
-- is the one-segment case. Read allocates nothing once a path has been seen (the split is cached),
-- which is what the settingsRead scenario's ceiling in tests/perf.lua holds it to.
NS.ResolvePath, NS.SetPath = SchemaLib.Read, SchemaLib.Write

-- The bulk bracket (debug-logging-§10): a bulk copy or reset is ONE `[Set] <act> <scope>: N rows`
-- line, N the rows whose stored value moved; nested brackets are one act; a level that reset the
-- whole profile silences the line (OnProfileReset logs that once); a raised error marks the line
-- ` (stopped by an error)` and is re-raised unchanged. Run hands its walk an `info` table.
NS.Bulk = { Begin = S.BulkBegin, End = S.BulkEnd, Run = S.BulkRun }

-- The profile reset's count (debug-logging-§10). `[Set] reset profile '<name>' to defaults (N rows)`
-- is OnProfileReset's line, and N is the rows the reset CHANGED. Only a caller that runs before the
-- reset can know that, so every reset this addon drives goes through NS.ResetProfileCounted, which
-- leaves the number pending for the handler to take once (NS.ConsumeResetCount); the count is
-- cleared when the reset returns or raises. The minimap row is not counted, for the same reason a
-- sessionOnly row is not: a profile reset cannot reach it (its value is in the GLOBAL store). Nor is
-- a profiles-page row, which AceDBOptions owns.
local function reachedByProfileReset(row)
    return row.path ~= MINIMAP_PATH and row.page ~= "profiles"
end

function NS.ResetProfileCounted(db)
    S.ResetCounted(function() db:ResetProfile() end, reachedByProfileReset)
end

NS.ConsumeResetCount = S.ConsumeResetCount

-- ---------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------

--- Rows for one page. `unit` (optional) filters to the rows carrying that `unit` tag plus every
--- untagged row; no row carries one today, and omitting it returns every row of the page, which is
--- what RestoreDefaults / RestoreAllDefaults / `/rm list` want.
function NS.SchemaForPage(pageKey, unit)
    local out = {}
    -- Track each group's first-seen registration index so groups stay in the order their rows
    -- were registered. Sorting purely on row.order would interleave groups (every group's
    -- order=10 row clustering before any order=20 row), which breaks the section-header layout.
    local groupIndex = {}
    for _, row in ipairs(NS.Schema) do
        if row.page == pageKey and (unit == nil or not row.unit or row.unit == unit) then
            out[#out + 1] = row
            local g = row.group or ""
            if groupIndex[g] == nil then
                groupIndex[g] = #out
            end
        end
    end
    table.sort(out, function(a, b)
        local ga, gb = groupIndex[a.group or ""], groupIndex[b.group or ""]
        if ga ~= gb then return ga < gb end
        return (a.order or 100) < (b.order or 100)
    end)
    return out
end

-- ---------------------------------------------------------------------
-- /rm list / /rm get value formatting
-- ---------------------------------------------------------------------

-- Rendering a stored value for display is LibKa0s-Slash-1.0's, so `/rm get`'s echo and the [Set]
-- debug line above can never disagree about how a color or an empty string reads. Kept under this
-- name because the schema layer is where callers look for it.
--
-- Resolved once, here at file load, and stashed (library-stack-§4). The TOC loads
-- libs\LibKa0s\LibKa0s.xml (which pulls in Slash.lua) in the lib block, long before
-- settings\Schema.lua, so by this line the major is either registered or permanently absent —
-- re-asking per call could never find it later. It mattered because this sits on the write seam
-- every panel widget and every `/rm set` goes through.
local SlashLib = LibStub and LibStub("LibKa0s-Slash-1.0", true)

-- The library-absent fallback is deliberately minimal, and stays that way: its only caller is the
-- [Set] debug line above, which is gated behind NS.State.debug and in that build is handed to a
-- NS.DebugLog stub that swallows it. Nothing renders these strings to a user, so re-growing the
-- typed branches here would be a second copy of a formatter this extraction exists to delete
-- (testing-§8). tests/test_schema.lua pins both arms.
function NS.FormatSchemaValue(row, v)
    if SlashLib then return SlashLib.FormatValue(row, v) end
    if v == nil then return "nil" end
    return tostring(v)
end

-- ---------------------------------------------------------------------
-- The selection-relative paths: `container.<field>` and `bandSet.<field>`
-- ---------------------------------------------------------------------
--
-- Containers and band sets are made by the player at runtime, so no row can name one by id. A row on
-- the Containers page is spelled `container.<field>` and means the SELECTED container's field; a row
-- on the Band sets page, `bandSet.<field>`, the selected band set's (design spec 5.6). The selection
-- is session state (NS.State.selectedContainer / selectedBandSet, never persisted), written only by
-- NS.SelectContainer and NS.SelectBandSet below: the page banners, `/rm select` and `/rm bands`.
-- A selection that names nothing (a fresh login, a delete) reads the first in order, so `/rm get
-- container.unit` always means something while a container exists.
--
-- ONE WRITER EACH. A container belongs to modules/ContainerManager.lua and a band set to
-- modules/BandSets.lua (architecture-§5), so a stamped row's `set` hands the value to NS.CM.SetField
-- or NS.BandSets.SetField (the name to Rename) rather than letting the seam store it at a path. The
-- write still goes through NS.SetByPath, so the panel, `/rm set` and every reset take one route, log
-- one [Set] line and validate once. A row whose field stores nil for "none" declares `nilAs`, the
-- value nil reads as (0 for a band-set reference), which its set turns back into nil; a row whose
-- field stores "" for "the skin's" or "Solid" declares `emptyAs`, the word "" reads as, because the
-- CLI cannot type an empty value.

local function noop() end

--- The selected container, and its id; else the first in order; else nil.
--- @return table|nil container, number|nil id
function NS.SelectedContainer()
    local CM = NS.CM
    if not (CM and CM.Get and NS.db) then return nil end
    local id = NS.State.selectedContainer
    local c = id ~= nil and CM.Get(id) or nil
    if c then return c, id end
    id = CM.List()[1]
    if id == nil then return nil end
    return CM.Get(id), id
end

--- The selected band set, and its id; else the first (the default set); else nil.
--- @return table|nil set, number|nil id
function NS.SelectedBandSet()
    local B = NS.BandSets
    if not (B and B.Get and NS.db) then return nil end
    local id = NS.State.selectedBandSet
    local set = id ~= nil and B.Get(id) or nil
    if set then return set, id end
    id = B.DefaultId()
    if id == nil then return nil end
    return B.Get(id), id
end

--- Select container `id` (nil: the first). Refuses an id that names no container.
function NS.SelectContainer(id)
    if id ~= nil and not (NS.CM and NS.CM.Get(id)) then return false end
    NS.State.selectedContainer = id
    return true
end

--- Select band set `id` (nil: the default). Refuses an id that names no band set.
function NS.SelectBandSet(id)
    if id ~= nil and not (NS.BandSets and NS.BandSets.Get(id)) then return false end
    NS.State.selectedBandSet = id
    return true
end

--- After `deletedIndex` of `ids` (the order as it was BEFORE the delete) went, the id that took its
--- place: the next one, else the one before it, else nil. A delete re-selects the neighbor, never
--- the first in the list.
function NS.NeighborAfterDelete(ids, deletedIndex)
    return ids[deletedIndex + 1] or ids[deletedIndex - 1]
end

local SELECTION = {
    [CONTAINER] = {
        selected = function() return NS.SelectedContainer() end,
        template = function() return NS.CONTAINER_TEMPLATE end,
        write = function(id, field, v)
            if field == "name" then return NS.CM.Rename(id, v) end
            return NS.CM.SetField(id, field, v)
        end,
        none = function() return NS.L["No container exists yet: create one with /rm new."] end,
    },
    [BANDSET] = {
        selected = function() return NS.SelectedBandSet() end,
        template = function() return NS.BANDSET_TEMPLATE end,
        write = function(id, field, v)
            if field == "name" then return NS.BandSets.Rename(id, v) end
            return NS.BandSets.SetField(id, field, v)
        end,
        none = function() return NS.L["No band set exists yet."] end,
    },
}

local function copyValue(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copyValue(x) end
    return out
end

--- The template a selection-relative row's path is checked against: a copy of the registry's
--- template with each `nilAs` row's declared value filled in where the template holds nil.
local function validationRoot(prefix)
    local sel = SELECTION[prefix]
    local root = copyValue(sel.template())
    for _, row in ipairs(NS.Schema) do
        local field = type(row.path) == "string" and row.path:match("^" .. prefix .. "%.(.+)$")
        if field and row.nilAs ~= nil and SchemaLib.Read(root, field) == nil then
            SchemaLib.Write(root, field, row.nilAs)
        end
    end
    return root
end

--- The row's read: the selected item's field, nil reading as the row's `nilAs`.
local function stampGet(row, sel, field)
    return function()
        local item = sel.selected()
        if not item then return nil end
        local v = SchemaLib.Read(item, field)
        if v == nil then return row.nilAs end
        if v == "" and row.emptyAs ~= nil then return row.emptyAs end
        return v
    end
end

--- The row's write: the value to the registry's writer for the selected item.
local function stampSet(row, sel, field)
    return function(v)
        local _, id = sel.selected()
        if id == nil then return end
        if row.nilAs ~= nil and v == row.nilAs then v = nil end
        if row.emptyAs ~= nil and v == row.emptyAs then v = "" end
        sel.write(id, field, v)
    end
end

--- The row's check: refused while nothing is selected, then the row's own validate.
local function stampValidate(row, sel)
    local own = row.validate
    return function(v, rid)
        if not sel.selected() then return false, sel.none() end
        if own then return own(v, rid) end
        return true
    end
end

--- Make `rows` selection-relative: each row's get, set and validate as above, its default from the
--- registry's template (the row's own only where the template holds nil), and a declared no-op reaction where it has none (the
--- writer asks for the apply itself). Answers `rows`, for NS.RegisterSchemaRows.
function NS.StampSelectionRows(rows)
    for _, row in ipairs(rows) do
        local prefix, field = tostring(row.path):match("^(%a+)%.(.+)$")
        local sel = SELECTION[prefix]
        if sel then
            -- The template is the one place a default is written (savedvariables-§2): it wins over a
            -- composer's built-in default, and only a field it leaves nil takes the row's own.
            local v = SchemaLib.Read(sel.template(), field)
            if v == nil then v = row.default end
            if v == nil then v = row.nilAs end
            row.default = copyValue(v)
            row.get, row.set = stampGet(row, sel, field), stampSet(row, sel, field)
            row.validate = stampValidate(row, sel)
            row.onChange = row.onChange or noop
        end
    end
    return rows
end

-- ---------------------------------------------------------------------
-- Schema-shape validation
-- ---------------------------------------------------------------------
--
-- Run once at panel-registration time after every settings/<page>.lua has loaded its rows. The
-- library's check: a row that is not a table, a missing path, a type or page outside the sets
-- below, a missing `group` (options-ui-§13), a duplicate path, and (architecture-§5) a path that
-- does NOT resolve against the defaults that hold it -- a typo'd path would otherwise silently
-- read and write nothing. It only PRINTS; it never refuses to register.
--
-- A page is where a row is EDITED, never where it is stored. The Containers page's five rail entries
-- are a page key each (settings/Containers.lua), and the Band sets page is one.
local VALID_PAGES = {
    general = true, profiles = true, bandsets = true,
    containers = true, containers_display = true, containers_indicator = true,
    containers_visibility = true, containers_sounds = true,
}

--- Which defaults tree a row's path resolves against. Almost every row means `defaults.profile`; a
--- `global.` path means `defaults.global`. Two kinds of row answer no root and so are skipped:
--- a profiles-page row, which is AceDBOptions-supplied and in no defaults tree, and a row that
--- OWNS ITS STORAGE (its own `get`), whose path is not where its value lives. That second kind is
--- architecture-§5's one sanctioned exemption, and the minimap row is its case here: its path
--- `global.minimap.shown` names the row's sense, its value is LibDBIcon's `minimap.hide` behind
--- the row's inverting get/set (core/Data.lua), and a `shown` default must never exist to resolve
--- against (anti-pattern #81). A sessionOnly row is skipped by the library itself: its value is
--- deliberately not in the profile.
local function defaultsRoot(parts, row)
    -- A selection-relative row owns its get and set (they reach the registry's writer), but its path
    -- still names a template field, and that is what must resolve: a typo there reads and writes
    -- nothing on every container.
    if parts[1] == CONTAINER then return validationRoot(CONTAINER), 2 end
    if parts[1] == BANDSET then return validationRoot(BANDSET), 2 end
    if row.page == "profiles" or type(row.get) == "function" then return nil end
    local d = NS.defaults
    if parts[1] == "global" then return d and d.global, 2 end
    return d and d.profile, 1
end

--- Walk the assembled schema and surface any malformed row. Returns three counts for the test
--- harness to assert: shape `errors`, paths `resolved` against the defaults that hold them, and
--- `missing` paths (present rows whose path has no matching default).
function NS.ValidateSchema()
    return S.Validate({ pages = VALID_PAGES, defaultsRoot = defaultsRoot })
end

-- The type-aware value parser moved to LibKa0s-Slash-1.0 (`lib.ParseValue`): clamping, the
-- case-sensitive enum check, the 0-1 / 0-255 color rescale and the nil-plus-reason failure
-- contract all live there, and settings/Slash.lua hands the library the schema rows to parse
-- against. Nothing here called it once the dispatcher was extracted, and a second copy of a parser
-- is precisely the drift the extraction exists to end.
