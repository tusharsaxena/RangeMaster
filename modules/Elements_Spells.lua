local _, NS = ...
-- modules/Elements_Spells.lua — the spell chips (design spec 5.3): one icon per spell in the
-- element's `list`, each colored by that spell's own range answer (NS.Range.InSpellRange):
-- in range green, out of range red, no answer (unknown spell, unusable, no unit) gray. Style "chip"
-- colors the chip's edge; "icon" tints the icon itself. The element contract is
-- modules/Elements_Number.lua's.
--
-- THE CHIPS ARE POOLED (core/PoolSetup.lua, LibKa0s-Pool-1.0's array pool, one per element): Style
-- parks every chip and takes one per spell back, so a re-apply builds nothing new and the chip at
-- position n is the frame it was. Each chip remembers the answer it last drew, so a render that
-- changes no answer paints nothing.

NS.Elements = NS.Elements or {}
local Spells = {}
NS.Elements.Spells = Spells

local Style = NS.Style
local C = NS.Constants
local Pool = NS.Pool

local GAP = 2
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local UNSET = {}   -- a chip that has drawn no answer yet

-- The three answers, as stored colors (true, false, and nil read through the key "none").
local ANSWER = { [true] = C.HexColor(C.BAND_RAMP[1]), [false] = C.HexColor(C.BAND_RAMP[#C.BAND_RAMP]),
                 none = C.HexColor(C.UNKNOWN_COLOR) }

local function newChip(parent)
    local chip = CreateFrame("Frame", nil, parent)
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetAllPoints(chip)
    chip.edge = Style.NewEdges(chip, "OVERLAY")
    Style.LayEdges(chip, chip.edge, 1)
    return chip
end

function Spells.Build(inst)
    local frame = CreateFrame("Frame", nil, inst.overlay)
    return { frame = frame, pool = Pool.New(), chips = {}, w = 0, h = 0 }
end

local function dress(chip, parent, id, size, x, edged)
    local icon = id and select(2, NS.Compat.GetSpellInfo(id))
    chip.icon:SetTexture(icon or NO_ICON)
    chip.icon:SetVertexColor(1, 1, 1, 1)
    chip:SetSize(size, size)
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
    for _, t in ipairs(chip.edge) do t:SetShown(edged) end
    chip.result = UNSET
end

function Spells.Style(el, cfg)
    local size = tonumber(cfg.size) or 20
    local list = type(cfg.list) == "table" and cfg.list or {}
    local edged = cfg.style ~= "icon"
    Pool.ReleaseAll(el.pool)
    local parent = el.frame
    local function make() return newChip(parent) end
    for i, id in ipairs(list) do
        dress(Pool.Acquire(el.pool, make), parent, id, size, (i - 1) * (size + GAP), edged)
    end
    el.chips, el.edged = el.pool.active, edged
    el.w = #list > 0 and (#list * size + (#list - 1) * GAP) or 0
    el.h = #list > 0 and size or 0
end

function Spells.Paint() return false end

--- Each chip whose answer moved is painted once.
function Spells.Update(el, _, ctx)
    local results = ctx.spells
    for i, chip in ipairs(el.chips) do
        local r = results[i]
        if r == nil then r = "none" end
        if chip.result ~= r then
            chip.result = r
            local c = ANSWER[r]
            if el.edged then
                Style.PaintEdges(chip.edge, c.r, c.g, c.b, c.a)
            else
                chip.icon:SetVertexColor(c.r, c.g, c.b, c.a)
            end
        end
    end
    return false
end
