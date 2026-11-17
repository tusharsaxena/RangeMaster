local addonName, NS = ...
-- settings/OptionsSetup.lua — the LibKa0s-Options-1.0 seam: the settings panel's descriptor, and its
-- load-completing degradation stub (options-ui-§1).
--
-- The settings-canvas shell, the schema-row to AceGUI translation, the two-column flow engine, the
-- header, the tab strip and the combat lock are the library's. This file is only the part that is
-- ours: where a value lives, which rows belong to which page, what a color looks like on disk, and
-- what "reset everything" may not touch. NS.Helpers IS the library instance.
--
-- LOAD-BEARING POSITION: after settings/Slash.lua and BEFORE every settings/<page>.lua, which call
-- NS.Helpers composers and NS.RegisterOptionsPage at file load.

local print = NS.Print

-- The brand, the library's parent title for the canvas and its header.
local PARENT_TITLE = NS.Constants.BRAND

-- ONE ROW SURVIVES EVERY RESET (launcher-§3): whether the minimap button is shown is a
-- per-installation preference, like the angle LibDBIcon keeps beside it. Enforced for the page's
-- Defaults walk by the schema runtime's `resetExempt` (settings/Schema.lua) and for Reset all
-- settings here.
local function survivesEveryReset(row)
    return row.path == NS.Constants.MINIMAP_PATH
end

-- The one rule about what the global reset must not touch, named once because it is enforced TWICE:
-- by the library through descriptor.skipRestoreAll, and by the stub's own reset loop below. The
-- Profiles rows are AceDBOptions' and resetting them deletes user data; every profile-backed row is
-- vetoed too, because the global reset IS a profile reset (options-ui-§12), so what the walk keeps is
-- what a profile reset cannot reach: the sessionOnly rows, whose storage is their own set().
local function vetoedFromResetAll(row)
    if survivesEveryReset(row) then return true end
    if row.page == "profiles" then return true end
    return not row.sessionOnly
end

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)

local descriptor = {
    parentTitle   = PARENT_TITLE,
    mainPanelName = "RangeMasterMainPanel",
    -- The FOLDER name, this file's first vararg (library-stack-§8, options-ui-§1): the route to the
    -- library's IdList help-mark art. Never a display label.
    addonName     = addonName,

    print = function(line) print(line) end,
    -- The combat lock's refusals and the parked registration's flush are the library's `[Cfg]` lines
    -- (debug-logging-§4), written through the gated sink.
    debug = function(tag, fmt, ...) NS.Debug(tag, fmt, ...) end,

    -- The single write seam (architecture-§5): a panel change takes the path `/rm set` takes.
    get          = function(path) return NS.GetSetting(path) end,
    set          = function(path, value) return NS.SetByPath(path, value) end,
    applyDefault = function(row) return NS.ApplyDefault(row) end,
    allRows      = NS.SchemaRuntime.AllRows,
    rowsForPage  = function(pageKey, filter) return NS.SchemaForPage(pageKey, filter) end,

    skipRestoreAll = vetoedFromResetAll,

    -- THE GLOBAL RESET IS A PROFILE RESET (options-ui-§12): AceDB empties the active profile, the
    -- defaults merge back, and OnProfileReset reaches core/RangeMaster.lua's profile handler, which
    -- re-reads the latch and refreshes the panel. Counted, so the handler's line carries the rows the
    -- reset changed (debug-logging-§10).
    resetProfile = function()
        local db = NS.db
        if db and db.ResetProfile then NS.ResetProfileCounted(db) end
    end,
    -- The Profiles sub-page exists, so the reset tooltips name it.
    profilesPage = true,

    -- The bulk pair: a page's Defaults logs one `[Set] reset <page>: N rows` line.
    bulkBegin = NS.SchemaRuntime.BulkBegin,
    bulkEnd   = NS.SchemaRuntime.BulkEnd,

    scheduleTimer = function(fn, delay) return NS.addon:ScheduleTimer(fn, delay) end,
    getLSM        = function() return NS.GetLSM() end,
    validate      = function() NS.ValidateSchema() end,
    onAceGUI      = function(AceGUI) NS.AceGUI = AceGUI end,

    -- The landing body is the LIBRARY's (options-ui-§5): settings/About.lua decorates
    -- NS.Helpers.BuildMainContent with BuildLandingPage over its spec, read at render time.
    buildMain = function(ctx)
        if NS.Helpers and NS.Helpers.BuildMainContent then NS.Helpers.BuildMainContent(ctx) end
    end,

    -- Colors are stored as {r=, g=, b=, a=} named keys.
    colorDecode = function(c)
        if type(c) ~= "table" then c = {} end
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end,
    colorEncode = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end,
}

-- ---------------------------------------------------------------------------
-- The degradation stub: LOAD-COMPLETING (options-ui-§1)
-- ---------------------------------------------------------------------------
--
-- Page files call NS.Helpers composers at FILE LOAD; with them nil a page file raises, its
-- RegisterSchemaRows never runs, and part of the schema vanishes with the CLI and the defaults. So
-- the stub publishes every member a page file touches at load (measured by deleting one and
-- re-running the library-absent load; tests/test_optionssetup.lua and tests/test_surface_parity.lua
-- pin the set), keeps the global reset real, and makes everything else a no-op or one honest line.
-- No widget maker, flow engine, header or LAYOUT constant is copied here.
if not lib then
    local MISSING = NS.L["%s, so the settings panel is unavailable."]:format(NS.LIBKA0S_MISSING)

    local Helpers = {}
    NS.Helpers = Helpers

    -- Reached at load, so it must be real enough for a page file to finish.
    Helpers.LSMValues = function() return function() return {} end end

    -- The composers answer the EMPTY block: a host copy of a composed row is anti-pattern #73. The
    -- composed paths a host verb still writes (`enabled`, `locked`) are settings/Schema.lua's
    -- WRITE_THROUGH list. MasterControls keeps its two-value shape so General's call still destructures.
    for _, name in ipairs({ "ColorPair", "FontGroup", "BorderGroup", "BarGroup" }) do
        Helpers[name] = function() return {} end
    end
    Helpers.MasterControls = function() return {}, function() end end

    -- The global reset stays real: a player whose panel will not open is the one who needs it.
    Helpers.RestoreAllDefaults = function()
        NS.Bulk.Run("reset", "all", function(info)
            for _, row in ipairs(NS.Schema or {}) do
                if not vetoedFromResetAll(row) then NS.ApplyDefault(row) end
            end
            local db = NS.db
            if db and db.ResetProfile then
                NS.ResetProfileCounted(db)
                info.profileReset = true
            end
        end)
    end

    -- Reached only from a builder, a tab click or a user action, so a no-op is the honest answer.
    for _, name in ipairs({
        "CreatePanel", "EnsureDefaultsButton", "EnsureScroll", "ClearScroll", "Section",
        "AddSpacer", "AttachTooltip", "InlineButtonPair", "RenderField", "RenderGrid", "RenderRows",
        "RenderSchema", "SessionCheckbox", "RefreshAllPanels", "RestoreDefaults",
        "PatchAlwaysShowScrollbar", "SetRenderer",
        "SetChromeHeight", "TabStrip", "PageHeader", "RenderTabbedSchema",
    }) do
        Helpers[name] = function() end
    end
    Helpers.ChoiceGrid, Helpers.IdInput, Helpers.IdList = function() end, function() end, function() end
    Helpers.ResolveId         = function() return nil end
    Helpers.UnnamedCandidates = function() return nil end
    Helpers.ID_NAME_HINT      = {}
    Helpers.SelectTab         = function() end
    Helpers.NavRail           = function() end
    Helpers.SideTabs          = function() end
    Helpers.KeybindingsTab     = function() return nil end
    Helpers.KeybindRows        = function() return nil end
    Helpers.KEYBINDS_UNCHANGED = ""
    Helpers.StrataTooltip      = function() return "" end
    Helpers.ResetAllTooltip    = function(tail) return type(tail) == "string" and tail or "" end
    -- The skin entries (skinning-§3): the tab draws nothing, the picker answers nil, and the verb
    -- answers nil, "absent" so core/SkinSetup.lua prints the library-absent line.
    Helpers.AppearanceTab      = function()
        return { key = "Appearance", label = "Skin", render = function() end }
    end
    Helpers.AppearanceRows     = function() return nil end
    Helpers.SkinPicker         = function() return nil end
    Helpers.HideSkinPicker     = function() end
    Helpers.SkinVerb           = function() return nil, "absent" end
    Helpers.SkinNotice         = function() return nil, "unavailable" end
    Helpers.PositionBlock      = function() return {}, function() end end
    Helpers.LabelFont          = function() end
    Helpers.__panels   = function() return {} end
    Helpers.__panelFor = function() return nil end

    NS.RegisterOptionsPage = function() end
    NS.RefreshOptionsPanel = function() end
    NS.CreateOptionsPanel  = function() print(MISSING) end
    NS.OpenOptionsPanel    = function() print(MISSING) end
    return
end

-- NS.Helpers IS the instance, decorated in place (settings/About.lua adds BuildMainContent), never a
-- fresh table copying members across, so a suite that swaps a member swaps the one callers see.
NS.Helpers = lib:New(descriptor)
local Helpers = NS.Helpers

NS.RegisterOptionsPage = function(key, name, builder) Helpers.RegisterOptionsPage(key, name, builder) end
NS.CreateOptionsPanel  = function() Helpers.CreateOptionsPanel() end
NS.OpenOptionsPanel    = function() Helpers.OpenOptionsPanel() end
NS.RefreshOptionsPanel = function() Helpers.RefreshAllPanels() end
