local _, NS = ...
-- modules/Elements_Text.lua — the text element (design spec 5.3): the current band's label ("MID",
-- "OOR"), upper-cased when `upper` is set, in the band's text color. An unknown range reads the band
-- set's unknown label; no unit reads nothing. The element contract is modules/Elements_Number.lua's.
--
-- The label moves only with the band, so it is written in Paint, which the renderer calls only when
-- the band (or the set) changed: a render inside one band touches nothing here.

NS.Elements = NS.Elements or {}
local Text = {}
NS.Elements.Text = Text

local Style = NS.Style

--- The label for render context `ctx`, as stored (not yet upper-cased).
--- @return string
function Text.Label(ctx)
    if ctx.state == "none" then return "" end
    if ctx.row then return ctx.row.label or "" end
    local unknown = ctx.set and ctx.set.unknown
    return unknown and unknown.label or NS.Constants.UNKNOWN_LABEL
end

function Text.Build(inst)
    local frame = CreateFrame("Frame", nil, inst.overlay)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
    return { frame = frame, fs = fs, w = 0, h = 0 }
end

function Text.Style(el, cfg)
    el.size = Style.Font(el.fs, cfg)
    el.w, el.h, el.text = 0, el.size, nil
end

function Text.Paint(el, cfg, ctx)
    local text = Text.Label(ctx)
    if cfg.upper then text = text:upper() end
    el.fs:SetTextColor(Style.Color(cfg.colorMode, cfg.color, ctx, "textColor"))
    if text == el.text then return false end
    el.text = text
    el.fs:SetText(text)
    local w = Style.TextWidth(el.fs, text, el.size)
    if w == el.w then return false end
    el.w = w
    return true
end

function Text.Update() return false end
