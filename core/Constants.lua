local _, NS = ...
-- core/Constants.lua — addon-wide constants: fallback media, the brand, the logo paths, the minimap
-- path, the band color ramp and the layers table (frame-layering-§5).
NS.Constants = NS.Constants or {}
local C = NS.Constants

-- LibSharedMedia fallback paths, returned when LSM is absent or a media key does not resolve.
C.FALLBACK_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
C.FALLBACK_BORDER  = "Interface\\Tooltips\\UI-Tooltip-Border"
C.FALLBACK_FONT    = "Fonts\\FRIZQT__.TTF"

-- The debug console's monospace face (debug-logging-§2), from the LibKa0s payload through the
-- NS.MediaFont seam core/MediaSetup.lua publishes; that file MUST load before this one (the TOC says
-- so). THE FALLBACK IS A REAL CLIENT FONT, a literal that cannot be nil: SetFont accepts a path to a
-- file that is not there and simply draws nothing.
C.FONT_MONO = NS.MediaFont and NS.MediaFont("JetBrains Mono") or C.FALLBACK_FONT
-- The LibSharedMedia key the library registers the face under, kept beside the path.
C.FONT_MONO_NAME = "JetBrains Mono"

-- The landing page's logo (options-ui-§5), drawn at 300x300 by the library: a SEPARATE, larger file
-- from the icon below (layout-§4).
C.LOGO_PATH = "Interface\\AddOns\\RangeMaster\\media\\logos\\rangemaster.logo.tga"
-- The ICON-sized logo (layout-§4): the TOC's `## IconTexture`, the minimap button and a broker
-- display read it. 128x128, uncompressed 32-bit; an RLE or 24-bit TGA here draws nothing and raises
-- nothing (anti-pattern #82). The TOC spells this path again, because `## IconTexture` is read before
-- any Lua runs; tests/test_docs.lua pins the two spellings together.
C.LOGO_ICON_PATH = "Interface\\AddOns\\RangeMaster\\media\\logos\\rangemaster.logo.128.tga"

-- THE BRAND NAME, IN PLAIN TEXT, AND THERE IS EXACTLY ONE OF IT (launcher-§1): the LDB object's
-- `label`, the Slash dispatcher's `brandName`, the console's report markers and the options parent
-- title. Not the TOC's `## Title` and not the folder name.
C.BRAND = "Ka0s Range Master"

-- The minimap button's visibility, as the path a player types (launcher-§3). The row reads SHOWN; the
-- storage is LibDBIcon's own `global.minimap.hide`, inverted once at the read/write seam in
-- core/Data.lua, so no `shown` key is ever stored (anti-pattern #81). GLOBAL, because a minimap button
-- belongs to the installation and a profile switch must not move it.
C.MINIMAP_PATH = "global.minimap.shown"

-- The band color ramp, nearest band first, and the unknown band's gray (the design spec, section 5.2).
-- Read by the band-set presets and the editor's "new band" color; never typed at a call site.
C.BAND_RAMP = { "4ade80", "a3e635", "facc15", "fb923c", "ef4444" }
C.UNKNOWN_COLOR = "9ca3af"
C.UNKNOWN_LABEL = "?"

--- A stored color from a ramp entry: `{ r, g, b, a }` in 0..1, a NEW table every call, so no two
--- stored colors ever share one. `hex` is six hex digits, with or without a leading "#".
--- @return table
function C.HexColor(hex, a)
    hex = tostring(hex or ""):gsub("^#", "")
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    return { r = (r or 255) / 255, g = (g or 255) / 255, b = (b or 255) / 255, a = a or 1 }
end

-- ---------------------------------------------------------------------------
-- Frame layering (frame-layering-§1..§6)
-- ---------------------------------------------------------------------------
--
-- THE ONE LAYERS TABLE (frame-layering-§5). Every SetFrameStrata and SetFrameLevel this addon makes
-- reads it, and every level is an OFFSET over the frame that owns the band:
-- `base:GetFrameLevel() + LAYERS.LEVEL.<NAME>`. No call site hands SetFrameStrata a string literal or
-- SetFrameLevel a bare number; tests/test_layers.lua pins both.
--
-- THE ADDON'S STACK, lowest first. The v0.1.0 scaffold draws no frame of its own yet; the first row
-- is reserved for the range containers, and the rest are the library's and Blizzard's, listed so a
-- new frame is placed around known neighbors.
--
--   HUD      MEDIUM: a range container's root. Inside one container, from its own level L:
--              L + FILL     the background fill
--              L + BORDER   the border frame, above the fill
--              L + OVERLAY  the number, text, indicator and spell chips
--              L + HANDLE   the unlocked drag strip (LibKa0s-Widgets-1.0 DragHandle `level`)
--   Launcher MEDIUM, level 8: the LibDBIcon minimap button (LibDBIcon's choice).
--   Settings HIGH, toplevel: Blizzard's Settings panel; inside it the library's bands.
--   MODAL    DIALOG, toplevel: the LibKa0s debug console, perf panel and skin picker; Blizzard's
--            StaticPopups (the Reset-all confirmation) share it.
--   CHILD    FULLSCREEN: the LibKa0s copy window.
--   POPUP    FULLSCREEN_DIALOG: the color picker and menus.
--   CURSOR   TOOLTIP: GameTooltip.
C.LAYERS = {
    STRATA = {
        HUD = "MEDIUM",
    },
    LEVEL = {
        FILL    = 1,
        BORDER  = 2,
        OVERLAY = 4,
        HANDLE  = 50,
    },
}
