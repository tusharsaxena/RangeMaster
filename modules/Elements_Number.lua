local _, NS = ...
-- modules/Elements_Number.lua — the number element (design spec 5.3): the range bracket written in
-- one of six formats, in the band's text color.
--
--   NS.Elements.Number.Format(fmt, state, minYd, maxYd, unknownLabel) -> string
--       on (20, 25): range "20–25", max "25", min "20", under "<25", approx "~22" (the floor of the
--       midpoint), suffix "25 yd"; an open-ended bracket (40, nil) reads "40+" in EVERY format;
--       unknown reads `unknownLabel` (the band set's, "?" when none is given); no unit reads "".
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
                 suffix = "45 yd" }

function Number.Build(inst)
    local frame = CreateFrame("Frame", nil, inst.overlay)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
    return { frame = frame, fs = fs, w = 0, h = 0 }
end

function Number.Style(el, cfg)
    el.size = Style.Font(el.fs, cfg)
    el.minW = math.ceil(#(SAMPLE[cfg.format] or SAMPLE.range) * el.size * 0.6)
    el.w, el.h, el.text = el.minW, el.size, nil
end

function Number.Paint(el, cfg, ctx)
    el.fs:SetTextColor(Style.Color(cfg.colorMode, cfg.color, ctx, "textColor"))
    return false
end

function Number.Update(el, cfg, ctx)
    local text = Number.Format(cfg.format, ctx.state, ctx.lo, ctx.hi, ctx.unknownLabel)
    if text == el.text then return false end
    el.text = text
    el.fs:SetText(text)
    local w = math.max(el.minW, Style.TextWidth(el.fs, text, el.size))
    if w == el.w then return false end
    el.w = w
    return true
end
