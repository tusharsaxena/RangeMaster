local _, NS = ...
-- settings/General.lua — the General page: the Master controls tab and the Skin tab.
--
--     [ Master controls ][ Skin ]
--
--     Master controls  [Enable Range Master]  [General visibility]
--                      [Master scale]         [Master opacity]
--                      [Lock frame]           [Debug console]
--                      [Minimap button]       [Test mode]
--                      [Sim mode]
--                      [Reset position]       [Reset all settings]   <- the button pair, afterGroup
--
-- MASTER CONTROLS LEADS, AND IS NOT OPTIONAL (options-ui-§15). It is COMPOSED, never typed out:
-- H.MasterControls emits the block from one declaration, so no Ka0s addon can drift into its own
-- order (anti-pattern #73). What this file supplies is the part that is genuinely ours: the defaults
-- each row starts from, the `onChange` each fires, and the storage of the rows whose value is not in
-- the profile. The range containers are positionable displays, so no frame row is omitted, and the
-- addon has both a Test mode (session-only placeholders) and a Sim mode beside it.

local L = NS.L
local print = NS.Print
local H = NS.Helpers
local defaults = NS.defaults.profile

-- The session rows' paths, VERBATIM and unprefixed: session state lives outside the block's own
-- prefix. Named once because the registration below spells the same strings.
local DEBUG_CONSOLE_PATH = "state.debugConsole"
local TEST_MODE_PATH = "state.testMode"
local SIM_PATH = "state.sim"

-- The console row is bound to the console WINDOW's own show/hide state (options-ui-§15: session-only).
-- `ConsoleCheckbox` is the `{ label, tooltip, get, set }` pair both arms of core/DebugLogSetup.lua
-- publish, so a library-less build gets an honest toggle rather than a row wired to nothing.
local consoleCheckbox = NS.DebugLog and NS.DebugLog.ConsoleCheckbox and NS.DebugLog:ConsoleCheckbox()

local masterRows, masterTail = H.MasterControls({
    prefix           = "",
    page             = "general",
    addonName        = "Range Master",
    -- Not frameless: the range containers are positionable displays. Stated rather than left to the
    -- default, because `frameless` is the one field that silently REMOVES four mandated rows.
    frameless        = false,
    debugConsolePath = DEBUG_CONSOLE_PATH,
    -- The minimap button's row (launcher-§3): stored in the GLOBAL store, under LibDBIcon's own key,
    -- with the row's get/set inverting onto it (core/Data.lua).
    minimapPath      = NS.Constants.MINIMAP_PATH,
    -- Test mode (preview-mode): a session-only checkbox whose get/set are core/RangeMaster.lua's one
    -- writer, stamped below.
    testModePath     = TEST_MODE_PATH,
    -- Sim mode, BESIDE Test mode (options-ui-§15, OptionsCompose minor 19): the launcher descriptor's
    -- own pair, so ticking is `/rm sim on` and unticking is `/rm sim off`. Nothing is stored.
    isSimMode        = function() return NS.IsSimMode() end,
    toggleSim        = function() NS.ToggleSimMode() end,
    simPath          = SIM_PATH,
    notes            = {
        testMode = L["Refused in combat, and entering combat turns it off."],
    },
    defaults         = {
        enabled    = defaults.enabled,
        visibility = defaults.visibility,
        scale      = defaults.scale,
        alpha      = defaults.alpha,
        locked     = defaults.locked,
    },
    -- The same handler `/rm resetposition` calls, so the button and the verb cannot diverge.
    onResetPosition  = function() NS.ResetPositions() end,
    -- options-ui-§12's global reset, through the confirmation the act carries.
    onResetAll       = function() StaticPopup_Show("RANGEMASTER_RESET_ALL") end,
})

-- The composer emits DATA; `onChange` is the host's half. Keyed by PATH rather than by index, so a
-- change to the canonical order upstream cannot silently move a handler onto the wrong row.
local masterOnChange = {
    -- THE ADDON-WIDE SWITCH, AND IT IS NOT A DRAW GATE: it moves the `disabled` hold on the one latch
    -- (core/LifecycleSetup.lua), whose StandDown unregisters everything (slash-commands-§7).
    ["enabled"] = function() NS.SyncEnabledHold() end,
    -- Declared no-ops until the range containers exist to read them (the v0.1.0 plan, Tasks 5 to 7):
    -- each container reads the stored value when it renders. A row that deliberately does nothing
    -- has to SAY so, or the next reader takes the absence for an oversight.
    ["visibility"] = function() end,
    ["scale"]      = function() end,
    ["alpha"]      = function() end,
    ["locked"]     = function() end,
    -- The console's visibility is the ConsoleCheckbox's own `set`, stamped below.
    [DEBUG_CONSOLE_PATH] = function() end,
    -- The minimap button moves in the row's own `set` (NS.SetMinimapShown, core/Data.lua).
    [NS.Constants.MINIMAP_PATH] = function() end,
    -- Each mode's writer (core/RangeMaster.lua) announces MODE_CHANGED and refreshes the panel itself.
    [TEST_MODE_PATH] = function() end,
    [SIM_PATH] = function() end,
}

-- Published for the write-through path (settings/Schema.lua's WRITE_THROUGH and its announce): on a
-- load where H.MasterControls is the Options stub's hollow composer, `enabled` and `locked` have no row,
-- yet `/rm enable` and `/rm lock` still write them, and the announce looks the reaction up here.
NS.MasterReactions = masterOnChange

-- The rows whose storage is not the profile carry their own get/set, which LibKa0s-Schema-1.0
-- consults before it walks a path.
local rowStorage = {
    [NS.Constants.MINIMAP_PATH] = { get = NS.MinimapShown, set = NS.SetMinimapShown },
    [DEBUG_CONSOLE_PATH]        = consoleCheckbox,
    [TEST_MODE_PATH]            = {
        get = function() return NS.IsTestMode() end,
        set = function(v) NS.SetTestMode(v, "settings") end,
    },
}

for _, row in ipairs(masterRows) do
    local fn = masterOnChange[row.path]
    if fn then row.onChange = fn end
    local storage = rowStorage[row.path]
    if storage then row.get, row.set = storage.get, storage.set end
end

NS.RegisterSchemaRows(masterRows)

-- ── General > Skin ──────────────────────────────────────────────────────────────────────────
--
-- The skin this addon wears (skinning-§2: per addon, per profile). The tab is the library's
-- O.AppearanceTab, keyed "Appearance" and labeled "Skin", which draws every one of these as its own
-- controls, so all carry `skipRender`; they stay schema rows so the defaults resolve, every reset
-- reaches them, and `/rm get|set skin.skin` validates against `values`. With no Keybindings tab the
-- Skin tab is last (skinning-§3).
--
-- Each onChange applies ONLY its own half (core/SkinSetup.lua says why).
local SKIN_GROUP = "Appearance"
local skinDefaults = NS.defaults.profile.skin
NS.RegisterSchemaRows({
    { path = "skin.source", page = "general", group = SKIN_GROUP, order = 10, skipRender = true,
      type = "string", widget = "Dropdown", values = NS.SKIN_SOURCE_OPTIONS,
      default = skinDefaults.source, label = L["Skin source"],
      desc = L["Where this addon's look comes from: the Ka0s skin chosen below, or EllesmereUI."],
      onChange = function(v) NS.ApplySkinChoice(v, nil) end },
    { path = "skin.skin", page = "general", group = SKIN_GROUP, order = 20, skipRender = true,
      type = "string", widget = "Dropdown", values = NS.SKIN_OPTIONS,
      default = skinDefaults.skin, label = L["Skin"],
      desc = L["The Ka0s skin this addon wears. Changes the range displays, the tool windows and the settings pages right away."],
      onChange = function(v) NS.ApplySkinChoice(nil, v) end },
    { path = "skin.ignorePanel", page = "general", group = SKIN_GROUP, order = 30, skipRender = true,
      type = "bool", default = skinDefaults.ignorePanel, label = L["Ignore settings panel"],
      desc = L["Keep this addon's settings panel in the game's own look. Its other surfaces still wear the skin."],
      onChange = function(v) NS.ApplySkinIgnore(v, nil) end },
    { path = "skin.ignoreFonts", page = "general", group = SKIN_GROUP, order = 40, skipRender = true,
      type = "bool", default = skinDefaults.ignoreFonts, label = L["Ignore fonts"],
      desc = L["Keep every font in this addon as the game draws it. The skin still colors the text."],
      onChange = function(v) NS.ApplySkinIgnore(nil, v) end },
    { path = "skin.font", page = "general", group = SKIN_GROUP, order = 50, skipRender = true,
      type = "string", widget = "EditBox", dialogControl = "EditBox",
      default = skinDefaults.font, label = L["Font"],
      desc = L["The font this addon's text uses, over the skin's own. Empty keeps the skin's."],
      onChange = function(v) NS.ApplySkinOverride(v, nil) end },
    { path = "skin.texture", page = "general", group = SKIN_GROUP, order = 60, skipRender = true,
      type = "string", widget = "EditBox", dialogControl = "EditBox",
      default = skinDefaults.texture, label = L["Texture"],
      desc = L["The texture this addon's displays use, over the skin's own. Empty keeps the skin's."],
      onChange = function(v) NS.ApplySkinOverride(nil, v) end },
    { path = "skin.outline", page = "general", group = SKIN_GROUP, order = 65, skipRender = true,
      type = "string", widget = "Dropdown", values = NS.SKIN_OUTLINE_OPTIONS,
      default = skinDefaults.outline, label = L["Font outline"],
      desc = L["Where the skin outlines this addon's text: all of it, its HUD text only, or nowhere."],
      onChange = function(v) NS.ApplySkinOutline(v) end },
    -- The first-run skin picker's memory: set when the picker closes, so it shows once per profile.
    { path = "skin.pickerSeen", page = "general", group = SKIN_GROUP, order = 70, skipRender = true,
      type = "bool", default = skinDefaults.pickerSeen, label = L["Skin picker seen"],
      desc = L["Whether the first-run skin picker was closed on this profile."],
      onChange = function() end },
})

-- skinning-§3: the Skin tab, the library's own entry. `get` and `set` are core/SkinSetup.lua's read
-- and write seams, so a pick lands through NS.SetByPath like every other setting.
local SKIN_TAB = H.AppearanceTab({ get = NS.SkinChoice, set = NS.WriteSkinChoice })

-- "Reset all settings": irreversible, so confirmed. OnAccept calls NS.Helpers.RestoreAllDefaults, the
-- same helper `/rm resetall` calls, so the popup and the slash never diverge.
StaticPopupDialogs["RANGEMASTER_RESET_ALL"] = {
    -- THE COLLECTION'S ONE WORDING (options-ui-§12), verbatim.
    text         = L["Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded \226\128\148 your other profiles are not affected."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function()
        if NS.Helpers and NS.Helpers.RestoreAllDefaults then
            NS.Helpers.RestoreAllDefaults()
            print(L["All settings reset to defaults."])
        else
            print(L["Cannot reset settings \226\128\148 the settings helpers failed to load."])
        end
    end,
}

local function build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then
        return nil
    end

    local ctx = H.CreatePanel("RangeMasterGeneralPanel", "General", {
        pageKey         = "general",
        defaultsButton  = true,
        defaultsTooltip = H.ResetAllTooltip and H.ResetAllTooltip(
            L["Restore every General setting on this profile to its addon default."])
            or L["Restore every General setting on this profile to its addon default."],
    })
    -- Parked, not wired: the Defaults button is built on first OnShow (EnsureDefaultsButton).
    ctx.panel.defaultsOnClick = function()
        H.RestoreDefaults("general", ctx)
    end

    -- Declared THROUGH SetRenderer: its OnShow builds the Defaults button and, in combat, covers the
    -- page until PLAYER_REGEN_ENABLED (the library's combat lock, options-ui-§2/§11), and it owns
    -- WHEN the body draws. ClearScroll leads the body because a page marked dirty draws again.
    H.SetRenderer(ctx, function(c)
        H.ClearScroll(c)
        -- RenderTabbedSchema: the page's groups become the strip (options-ui-§13). H.MASTER_GROUP is
        -- both the composer's group literal and the tab's label, read off the instance.
        H.RenderTabbedSchema(c, "general", { [H.MASTER_GROUP] = masterTail }, nil, { tabs = { SKIN_TAB } })
    end)

    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, "General")
end

if NS.RegisterOptionsPage then
    NS.RegisterOptionsPage("general", "General", build)
end
