local addonName, NS = ...
-- modules/Elements_Indicator.lua — the indicator element (design spec 5.3): one shape in the band's
-- indicator color. The element contract is modules/Elements_Number.lua's.
--
--   dot, ring, square, diamond,            this addon's white 128x128 art (media/textures/indicators/
--   triangle, hexagon, star                <shape>_<style>, drawn by tools/indicator_art.py), tinted
--                                          with SetVertexColor. The style is the finish: plain, matte
--                                          (the default), glossy, glowing, neon or gem. An unknown
--                                          shape draws the dot, an unknown or missing style matte.
--   bar                                    LibKa0s-Widgets-1.0's data bar (W.Bar), full in the nearest
--                                          band and empty in the farthest or an unknown one: it draws
--                                          the BAND's position, never a guessed distance. Without the
--                                          Widgets major, a flat strip in the band color.
--   icon                                   a spell's icon (`spellID`, else the first spell chip),
--                                          tinted; a question mark when neither names a spell
--
-- The bar and the spell icon take no style.
--
-- Everything moves only with the band, so Update is empty and Paint does the work.
--
-- THE BAR'S COLOR IS A NEW TABLE EACH PAINT. W.Bar's SetValues repaints its fill only when the color
-- it is handed is a different table from the last (libs/LibKa0s/WidgetsBar.lua, SetValues), so one
-- table refilled in place would be painted once and never again. Two tables alternate: each paint
-- hands the bar the one it does not hold, and a paint (a band change) allocates nothing.

NS.Elements = NS.Elements or {}
local Indicator = {}
NS.Elements.Indicator = Indicator

local Style = NS.Style
local C = NS.Constants
local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)

local SHAPES = { dot = true, ring = true, square = true, diamond = true, triangle = true, hexagon = true,
                 star = true }
local STYLES = { plain = true, matte = true, glossy = true, glowing = true, neon = true, gem = true }
local FLAT = "Interface\\Buttons\\WHITE8X8"
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- The icon `cfg` draws: its own spell's, else the container's first chip's (NS.CM.SpellChips).
local function iconOf(cfg, container)
    local id = cfg.spellID or NS.CM.SpellChips(container)[1]
    local icon = id and select(2, NS.Compat.GetSpellInfo(id))
    return icon or NO_ICON
end

function Indicator.Build(inst)
    local frame = CreateFrame("Frame", nil, inst.overlay)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(frame)
    return { frame = frame, tex = tex, w = 0, h = 0, colors = { { 1, 1, 1, 1 }, { 1, 1, 1, 1 } }, flip = 1,
             values = { value = 0, max = 1 } }
end

--- The data bar, built once per pooled frame on first need. Nil without LibKa0s-Widgets-1.0.
local function barOf(el)
    if el.bar or not (W and W.Bar) then return el.bar end
    el.bar = W.Bar(el.frame, { owner = addonName, style = W.BarStyle("mini", { showText = false }) })
    el.bar:SetAllPoints(el.frame)
    return el.bar
end

local function styleBar(el, size)
    el.w, el.h = size * 3, math.max(4, math.floor(size / 2))
    local bar = barOf(el)
    if bar then
        el.tex:Hide()
        bar:Show()
        return
    end
    el.tex:SetTexture(FLAT)
    el.tex:Show()
end

function Indicator.Style(el, cfg, container)
    local size = tonumber(cfg.size) or 12
    el.shape = cfg.shape
    if el.bar then el.bar:Hide() end
    if cfg.shape == "bar" then return styleBar(el, size) end
    el.w, el.h = size, size
    el.tex:Show()
    if cfg.shape == "icon" then
        el.tex:SetTexture(iconOf(cfg, container))
    else
        el.tex:SetTexture(C.INDICATOR_PATH .. (SHAPES[cfg.shape] and cfg.shape or "dot") .. "_"
            .. (STYLES[cfg.style] and cfg.style or "matte"))
    end
end

--- How full the bar is: the nearest band full, the farthest band 1/n, unknown or no unit empty.
local function fill(ctx)
    local n = ctx.set and #ctx.set.bands or 0
    if type(ctx.band) ~= "number" or n == 0 then return 0 end
    return (n - ctx.band + 1) / n
end

function Indicator.Paint(el, cfg, ctx)
    local r, g, b, a = Style.Color(cfg.colorMode, cfg.color, ctx, "indicatorColor", Style.SkinColor(cfg, "text"))
    if el.shape == "bar" and el.bar then
        el.flip = 3 - el.flip
        local c, v = el.colors[el.flip], el.values
        c[1], c[2], c[3], c[4] = r, g, b, a
        v.value, v.color = fill(ctx), c
        el.bar:SetValues(v)
    else
        el.tex:SetVertexColor(r, g, b, a)
    end
    return false
end

function Indicator.Update() return false end
