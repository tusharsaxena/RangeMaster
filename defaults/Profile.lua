local _, NS = ...
-- defaults/Profile.lua — the ONE place a default value is hardcoded (savedvariables-§2). Three shapes:
--
--   NS.defaults            what AceDB merges into a profile and into `global`: every schema row's
--                          stored default, mirrored here (architecture-§5). Addon-wide settings only.
--   NS.CONTAINER_TEMPLATE  the full shape of ONE range container (design spec 5.2). Containers are
--   NS.BANDSET_TEMPLATE    built by the player at runtime, so neither registry is an AceDB default:
--   NS.BAND_TEMPLATE       modules/ContainerManager.lua (Task 4) and modules/BandSets.lua deep-copy
--                          a template when a member is created, and core/Database.lua's load pass
--                          (PrepareProfile) fills any key a later build added into every stored
--                          member (`== nil`, never `or`, so a stored false survives; savedvariables-§5).
--
-- The registries' storage keys (profile.containers, containerOrder, nextContainerId, bandSets,
-- bandSetOrder, nextBandSetId, seeded) are created by that load pass, not declared here: they are
-- bookkeeping with no schema row, and an AceDB default with no row is a setting nobody can reach
-- (tests/test_schema.lua). docs/schema.md names each one.
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

-- ---------------------------------------------------------------------------
-- The registry templates (design spec 5.2)
-- ---------------------------------------------------------------------------

local C = NS.Constants
local function white() return C.HexColor("ffffff") end

--- One range container. `bandSet` is filled with NS.BandSets.DefaultId() on create and on load; a
--- nil `bandSetFriendly` means "use bandSet for every reaction". An empty `font` or `texture` is
--- "the skin's" (core/SkinSetup.lua), resolved by the renderer (Task 5).
NS.CONTAINER_TEMPLATE = {
    name = "", enabled = true, unit = "target",
    bandSet = nil, bandSetFriendly = nil,
    -- Each mode keeps its own placement, so a screen drag (or a new container's screen stagger)
    -- never carries onto a unit frame or the cursor: point/relPoint/x/y here are the screen's,
    -- `frame` holds the point on the unit frame (above it), `cursor` the offset from the cursor
    -- (below and right of it), and `nameplate` (below) the point on a plate.
    anchor = {
        mode = "screen",                                   -- "screen"|"frame"|"nameplate"|"cursor"
        frame = { provider = "blizzard", name = "",        -- "blizzard"|"ellesmere"|"custom"
                  point = "BOTTOM", relPoint = "TOP", x = 0, y = 2 },
        cursor = { point = "CENTER", x = 12, y = -40 },
        point = "CENTER", relPoint = "CENTER", x = 0, y = 0, strata = "MEDIUM",
    },
    -- sizing: "fit" sizes the container to its elements; "fixed" holds it at width x height (px),
    -- the elements centered in it (modules/Container.lua, Instance:Layout).
    layout = { direction = "row", spacing = 4, padding = 4, scale = 1, alpha = 1,
               sizing = "fit", width = 120, height = 28 },
    frame = {
        border = { enabled = true, texture = "", size = 1, colorMode = "band", color = white() },
        background = { enabled = false, colorMode = "band", color = C.HexColor("000000", 0.5), bandAlpha = 0.15 },
    },
    elements = {
        -- An ARRAY: the load pass never backfills it index by index; it appends a missing name once.
        order = { "indicator", "number", "text", "spells" },
        number = { enabled = true, format = "range", font = "", size = 14, outline = "OUTLINE",
                   shadow = false, colorMode = "band", color = white() },
        text = { enabled = false, font = "", size = 12, outline = "OUTLINE", shadow = false,
                 colorMode = "band", color = white(), upper = true },
        -- shape: dot|ring|square|diamond|triangle|hexagon|star|bar|icon; style (the art's finish,
        -- the shapes only): plain|matte|glossy|glowing|neon|gem (modules/Elements_Indicator.lua).
        indicator = { enabled = false, shape = "dot", style = "matte", size = 12, colorMode = "band",
                      color = white(), spellID = nil },
        -- `list` is the player's (seeded per client and class on create, Task 4); empty here, so the
        -- load pass has nothing to fill into it.
        spells = { enabled = false, list = {}, style = "chip", size = 20 },
    },
    visibility = { combat = "any", reaction = "any", hideNoUnit = true, oocAlpha = 1 },
    sounds = { enabled = false, channel = "Master" },
    nameplate = { includeFriendly = false, point = "TOP", relPoint = "BOTTOM", x = 0, y = -2 },
}

--- One band set. `bands` is ordered, contiguous from 0 and open-ended, which modules/BandSets.lua's
--- Normalize guarantees on every write and on load; it is empty here, so the load pass never fills
--- template bands into a stored set.
NS.BANDSET_TEMPLATE = {
    name = "",
    matchBy = "max",                                       -- "max"|"min": which bound picks the band
    unknown = { label = C.UNKNOWN_LABEL, color = C.HexColor(C.UNKNOWN_COLOR) },
    bands = {},
}

--- One band of a set. `to` nil is open-ended (infinity); `sound` is an LSM sound key or nil.
NS.BAND_TEMPLATE = {
    from = 0, to = nil, label = "",
    frameColor = C.HexColor(C.BAND_RAMP[1]), textColor = C.HexColor(C.BAND_RAMP[1]),
    indicatorColor = C.HexColor(C.BAND_RAMP[1]),
    sound = nil,
}
