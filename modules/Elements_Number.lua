local _, NS = ...
-- modules/Elements_Number.lua — the number element (design spec 5.3): the range bracket written in
-- one of six formats, in the band's text color.
--
--   NS.Elements.Number.Format(fmt, state, minYd, maxYd, unknownLabel) -> string
--       on (20, 25): range "20–25", max "25", min "20", under "<25", approx "~22" (the floor of the
--       midpoint), suffix "25 yd"; an open-ended bracket (40, nil) reads "40+" in EVERY format;
--       unknown reads `unknownLabel` (the band set's, "?" when none is given); no unit reads "".
--
--   NS.Elements.Number.BandSpan(ctx) -> string|nil
--       format "band": the span of the band being drawn rather than the bracket, its reach as the
--       spell answering it reports (AUTO "8–41" with Hawk Eye; MELEE "0–5"), a gap or yard band's own
--       yards, beyond from the reach before it ("41+"). Nil with no band (unknown, none): the caller
--       writes the bracket's format instead.
--   NS.Elements.Number.BracketOf(ctx) -> lo, hi
--       the bracket the formats write: ctx's, with the far bound pulled in to the ranged anchor's
--       min range while a dead-zone band is drawn (5-10 reads 5-8 on a Forever hunter).
--   NS.Elements.Number.Joins(c) -> boolean
--       whether container `c` writes its number and its band's label as ONE line (`layout.joinText`,
--       on by default; the owner, 2026-11-20: two cells of different widths read as slots). The text
--       element then draws nothing itself: this element writes "28+ OOR", the label in the text
--       element's color and case, in the order elements.order gives them.
--
-- ALIGNMENT (`layout.align`: left, center, right) places the line inside its cell, which keeps a
-- reserved width so the display does not grow and shrink as the figure moves.
--
-- HONEST BRACKETS. The engine answers a bracket, never a distance (modules/Range.lua), so a format
-- only chooses which bound to write. An open-ended bracket has no far bound, and no format invents
-- one: "max" on (40, nil) is "40+", not 40 and not 45.
--
-- The element itself follows the contract every element file shares (modules/Container.lua calls it):
--   Build(inst) -> el        the holder frame and its regions, made once per pooled frame
--   Style(el, cfg)           face and size, on every apply
--   Paint(el, cfg, ctx)      colors, only when the band changed; answers whether the width moved
--   Update(el, cfg, ctx)     the per-render part; answers whether the width moved
-- `el.w` and `el.h` are the cell the layout places.

NS.Elements = NS.Elements or {}
local Number = {}
NS.Elements.Number = Number

local Style = NS.Style
local L = NS.L

local DASH = "\226\128\147"   -- an en dash: "20–25"
local UNKNOWN = NS.Constants.UNKNOWN_LABEL

local function yd(v) return ("%d"):format(math.floor(v)) end

local CLOSED = {
    range  = function(lo, hi) return yd(lo) .. DASH .. yd(hi) end,
    max    = function(_, hi) return yd(hi) end,
    min    = function(lo) return yd(lo) end,
    under  = function(_, hi) return "<" .. yd(hi) end,
    approx = function(lo, hi) return "~" .. yd((lo + hi) / 2) end,
    suffix = function(_, hi) return L["%s yd"]:format(yd(hi)) end,
}

--- The bracket written in format `fmt` (an unknown format reads as "range").
--- @return string
function Number.Format(fmt, state, lo, hi, unknownLabel)
    if state == "none" then return "" end
    if state ~= "known" or (type(lo) ~= "number" and type(hi) ~= "number") then
        return type(unknownLabel) == "string" and unknownLabel or UNKNOWN
    end
    lo = type(lo) == "number" and lo or 0
    if type(hi) ~= "number" then return yd(lo) .. "+" end
    return (CLOSED[fmt] or CLOSED.range)(lo, hi)
end

-- The widest a format usually writes, so a cell does not shrink and grow as the figure moves.
local SAMPLE = { range = "40" .. DASH .. "45", max = "45", min = "40", under = "<45", approx = "~45",
                 suffix = "45 yd", band = "40" .. DASH .. "45" }
-- What a joined line reserves past the figure: a space and a five-letter label ("MELEE").
local JOIN_RESERVE = 6

local ALIGN = { left = "LEFT", center = "CENTER", right = "RIGHT" }

--- The reach a spell band's answering anchor reports, as (lo, hi) inside the band, or nil.
local function spellReach(b, r)
    local R = NS.Range
    local a = R and R.AnchorFor and R.AnchorFor(r.role, r.spells)
    local hi = a and a.maxRange
    if type(hi) ~= "number" or hi <= 0 then return nil end
    local lo = b.from or 0
    if r.role ~= "melee" and type(a.minRange) == "number" and a.minRange > lo then lo = a.minRange end
    return lo, hi
end

--- Band `i` of `set` as the span it covers: (lo, hi), hi nil when open-ended.
local function spanOf(set, i)
    local b = set.bands[i]
    local r = type(b.rule) == "table" and b.rule or nil
    local lo, hi = b.from or 0, b.to
    if r and r.type == "spell" then
        local slo, shi = spellReach(b, r)
        if slo then lo, hi = slo, shi end
    elseif r and r.type == "beyond" then
        for j = i - 1, 1, -1 do
            local rj = set.bands[j].rule
            if type(rj) == "table" and rj.type == "spell" then
                local _, h = spanOf(set, j)
                if h then lo = h end
                break
            end
        end
        hi = nil
    end
    return lo, hi
end

function Number.BandSpan(ctx)
    if ctx.state ~= "known" or type(ctx.band) ~= "number" or not (ctx.set and ctx.set.bands[ctx.band]) then
        return nil
    end
    local lo, hi = spanOf(ctx.set, ctx.band)
    if type(hi) ~= "number" then return yd(lo) .. "+" end
    return yd(lo) .. DASH .. yd(hi)
end

function Number.Joins(c)
    local e = c and c.elements
    return c ~= nil and c.layout ~= nil and c.layout.joinText == true and type(e) == "table"
        and type(e.number) == "table" and e.number.enabled == true
        and type(e.text) == "table" and e.text.enabled == true
end

--- Whether the text element comes before the number in `c`'s element order.
local function textFirst(c)
    for _, name in ipairs(c.elements.order or {}) do
        if name == "text" then return true end
        if name == "number" then return false end
    end
    return false
end

function Number.Build(inst)
    local frame = CreateFrame("Frame", nil, inst.overlay)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
    return { frame = frame, fs = fs, w = 0, h = 0 }
end

function Number.Style(el, cfg, c)
    el.size = Style.Font(el.fs, cfg)
    el.join = Number.Joins(c)
    el.textCfg = el.join and c.elements.text or nil
    el.textFirst = el.join and textFirst(c) or false
    local point = ALIGN[c and c.layout and c.layout.align] or "CENTER"
    el.fs:ClearAllPoints()
    el.fs:SetPoint(point, el.frame, point, 0, 0)
    el.fs:SetJustifyH(point)
    local chars = #(SAMPLE[cfg.format] or SAMPLE.range) + (el.join and JOIN_RESERVE or 0)
    el.minW = math.ceil(chars * el.size * 0.6)
    el.w, el.h, el.text, el.num, el.row = el.minW, el.size, nil, nil, nil
end

function Number.Paint(el, cfg, ctx)
    el.fs:SetTextColor(Style.Color(cfg.colorMode, cfg.color, ctx, "textColor", Style.SkinColor(cfg, "text")))
    return false
end

--- The joined line: the figure and the band's label, the label in the text element's color and case.
local function joined(el, num, ctx)
    local label = NS.Elements.Text.Label(ctx)
    if el.textCfg.upper then label = label:upper() end
    if label == "" then return num end
    if num == "" then num = nil end
    local r, g, b = Style.Color(el.textCfg.colorMode, el.textCfg.color, ctx, "textColor",
        Style.SkinColor(el.textCfg, "text"))
    local part = ("|cff%02x%02x%02x%s|r"):format(math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5), label)
    if not num then return part end
    if el.textFirst then return part .. " " .. num end
    return num .. " " .. part
end

--- The bracket to write: ctx's, its far bound pulled in to the ranged anchor's min range while a
--- dead-zone band is drawn. The gap holds only when that anchor says out of range and a shorter
--- check says near, so the unit is inside the min: a Forever hunter's 5-10 bracket reads 5-8 (the
--- owner, 2026-11-24; no checker sits at 8 yd). The band's own `to` stands in without an anchor.
local function bracketOf(ctx)
    local lo, hi, row = ctx.lo, ctx.hi, ctx.row
    local r = row and type(row.rule) == "table" and row.rule
    if ctx.state ~= "known" or not (r and r.type == "gap") then return lo, hi end
    local a = NS.Range and NS.Range.Anchor and NS.Range.Anchor("ranged")
    local edge = a and type(a.minRange) == "number" and a.minRange > 0 and a.minRange or row.to
    if type(edge) ~= "number" or (type(lo) == "number" and lo >= edge) then return lo, hi end
    if hi == nil or hi > edge then hi = edge end
    return lo, hi
end
Number.BracketOf = bracketOf

function Number.Update(el, cfg, ctx)
    local lo, hi = bracketOf(ctx)
    local num = cfg.format == "band" and Number.BandSpan(ctx)
        or Number.Format(cfg.format, ctx.state, lo, hi, ctx.unknownLabel)
    local text = num
    if el.join then
        -- Composed again only when the figure, the band or the set moved (a render inside one band
        -- with the same figure writes nothing).
        if num == el.num and ctx.row == el.row and ctx.set == el.set and ctx.state == el.st then return false end
        el.num, el.row, el.set, el.st = num, ctx.row, ctx.set, ctx.state
        text = joined(el, num, ctx)
    end
    if text == el.text then return false end
    el.text = text
    el.fs:SetText(text)
    local w = math.max(el.minW, Style.TextWidth(el.fs, text, el.size))
    if w == el.w then return false end
    el.w = w
    return true
end
