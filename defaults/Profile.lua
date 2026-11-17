local _, NS = ...
-- defaults/Profile.lua — the AceDB defaults tree: every schema row's stored default, mirrored here
-- (architecture-§5), plus the global store.
--
-- The v0.1.0 scaffold holds the Master controls and the skin choice. The range containers and band
-- sets join this tree with the data model (the v0.1.0 plan, Task 3; design spec section 5.2).
--
-- NOT HERE, deliberately: the debug flag, Test mode and Sim mode, which are session-only
-- (core/State.lua, debug-logging-§5, options-ui-§15), and the minimap row's `shown` sense, which is
-- LibDBIcon's `global.minimap.hide` inverted (core/Data.lua; launcher-§3, anti-pattern #81).

NS.defaults = NS.defaults or {}

NS.defaults.profile = {
    -- Master controls (options-ui-§15). `visibility` is the four-value dropdown from day one.
    enabled    = true,
    visibility = "always",
    scale      = 1.0,
    alpha      = 1.0,
    locked     = true,

    -- The skin this addon wears, per profile (skinning-§2). NS.DEFAULT_SKIN is core/SkinSetup.lua's
    -- client default (WoW Forever on Forever, Ka0s Default on Retail).
    skin = {
        source = "ka0s", skin = NS.DEFAULT_SKIN or "ka0s", ignorePanel = true, ignoreFonts = false,
        font = "", texture = "", outline = "hud", pickerSeen = false,
    },
}

NS.defaults.global = {
    -- 0, never the current version: AceDB strips a value equal to its default at logout and
    -- backfills it onto a legacy account (savedvariables-§1).
    schemaVersion = 0,

    -- LibDBIcon's own table (launcher-§3), global so a profile switch does not move the button.
    minimap = {
        hide = false,
    },
}
