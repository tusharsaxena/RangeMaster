local _, NS = ...
-- modules/Container.lua — the renderer (design spec 5.3): one pooled instance per enabled container,
-- its elements laid out by `elements.order`, painted from the shared band sets.
--
--   NS.Container.Acquire(id) -> inst     the live instance of container `id`, applied from its
--                                        settings now (a live id hands back the same instance)
--   inst:Render(state, minYd, maxYd, spellResults)   draw one range triple (NS.Range.Get's), the
--                                        spell answers indexed as the element's list
--   inst:Update(state, minYd, maxYd)     ask the spell answers, then Render
--   inst:Release()                       back to the pool: hidden, its watch dropped, nothing remembered
--   inst.bandIndex                       the band drawn: an index, "unknown", or "none" (no unit)
--   NS.Container.ForEach(fn)             fn(inst) for every live instance
--   NS.Container.UnitChanged(unit)       a different unit sits behind `unit`: its instances forget
--                                        what they drew, so the next render paints everything
--   NS.Container.Get(id), Sync(), Repaint(), StandDown()
--   NS.Container.AcquirePlate(id, token) -> inst   the instance of `nameplates` container `id` on
--                                        the plate behind `token` (modules/Anchors_Nameplate.lua
--                                        decides which plates get one), applied now
--   NS.Container.ReleasePlate(id, token), GetPlate(id, token), ForEachPlate(fn(inst, id, token))
--   inst:SetAnchorHidden(hidden)         the anchor's say: hidden while its frame or plate is missing
--
-- WHO DRIVES IT. CONTAINERS_CHANGED (modules/ContainerManager.lua, coalesced to the next frame and
-- held through combat) runs Sync: an instance for every enabled container, back to the pool for a
-- deleted or disabled one. BANDSETS_CHANGED runs Repaint. RANGE_UPDATED (modules/Ticker.lua, only on
-- change) reaches the instances watching that unit and no other: the cost scales with units read,
-- never with a per-container query. A skin change (the owner's OnLooksChanged) asks ContainerManager
-- for an apply (NS.CM.RequestApply), so the HUD face follows the skin on the next frame, and a change
-- that lands in combat (EllesmereUI repainting, a media registration) waits for the leave edge like
-- every other apply: nothing here is placed in combat.
--
-- A NEW UNIT BEHIND THE TOKEN. A retarget, a new focus, a mouseover, the player's pet, a plate token
-- handed to a new plate and a reaction change (core/RangeMaster.lua's unitChanged) run UnitChanged
-- here, then NS.Ticker.Changed, which sends the token's triple even when the bracket is the same. So
-- the band set is resolved again for the new unit's reaction (bandSetFriendly), the class color is
-- the new unit's, and every spell chip is asked again, whatever the bracket did.
--
-- SPELL CHIPS ARE ASKED EVERY READ. A spell's range edge can fall inside one LibRangeCheck bracket
-- (a 30 yd spell inside 28 to 35), where the triple never moves and RANGE_UPDATED never goes out.
-- The ticker's OnSteady hook reaches the instances on the unit read, and one with chips asks each
-- chip again and renders only when an answer moved. An instance without chips does nothing there.
--
-- PAINT ONLY WHAT CHANGED. A render recolors the border, the fill and every element only when the
-- band index or the band set differs from the last one drawn, and an element sets its text only when
-- the string differs (modules/Elements_*.lua). A render inside one band with the same figure touches
-- no region at all. The layout runs on an apply and when a cell's width moved.
--
-- THE POOL is LibKa0s-Pool-1.0's keyed shape (core/PoolSetup.lua), keyed by container id. The library
-- deliberately has no per-object release, and a renderer needs one (a deleted container, and plan
-- Task 6's recycled nameplate), so releaseKeyed below parks one object on the documented plain
-- `{ free, active }` shape, exactly as the library's ReleaseAllKeyed parks each.
--
-- PER-PLATE INSTANCES. A `nameplates` container has no single instance: it owns one per eligible
-- plate, from a second keyed pool keyed "<id>|<token>", each watching its plate token. Which plates
-- get one is the plate anchors' call (modules/Anchors_Nameplate.lua, NS.Plates); this file only
-- builds, applies and parks them, so it stays the one owner of every instance. A plate arrives and
-- goes in combat, so a plate instance is the one instance built or parked in combat: it is this
-- addon's own frame, anchored to a nameplate, which is no secure frame.
--
-- PLACEMENT is NS.Anchors.Apply (modules/Anchors.lua), which picks the mode and may hide the
-- instance (SetAnchorHidden) while the frame or plate it belongs on is missing. Every frame here is
-- this addon's own and none is protected, and an apply of a container never runs in combat: Sync is
-- reached only through CONTAINERS_CHANGED, which ContainerManager holds to PLAYER_REGEN_ENABLED (the
-- skin's re-apply included). A shown-state change is told to the anchors (NS.Anchors.ShownChanged),
-- so the cursor follow runs only while a cursor container is shown.

NS.Container = NS.Container or {}
local Container = NS.Container

local Perf = NS.Perf
local LAYERS = NS.Constants.LAYERS
local Style = NS.Style
local Pool = NS.Pool
local E = NS.Elements

local ELEMENT = { number = E.Number, text = E.Text, indicator = E.Indicator, spells = E.Spells }
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
                 FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

local pool = Pool.NewKeyed()
local platePool = Pool.NewKeyed()   -- the per-plate instances, keyed "<id>|<token>"
local byUnit = {}   -- [unit] = { [inst] = true }: the RANGE_UPDATED fan-out
local NO_SPELLS = {}

local Instance = {}
local InstanceMT = { __index = Instance }

function Instance:Show() self.frame:Show() end
function Instance:Hide() self.frame:Hide() end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function layer(root, offset)
    local f = CreateFrame("Frame", nil, root)
    f:SetAllPoints(root)
    Style.Stack(f, root, offset)
    return f
end

--- One pooled instance: the root, then the fill, the border and the overlay as levels over it.
local function newInstance()
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetFrameStrata(LAYERS.STRATA.HUD)
    local fill = layer(root, LAYERS.LEVEL.FILL)
    local bg = fill:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(fill)
    local borderFrame = layer(root, LAYERS.LEVEL.BORDER)
    return setmetatable({
        frame = root, fill = fill, background = bg, overlay = layer(root, LAYERS.LEVEL.OVERLAY),
        border = { frame = borderFrame, strips = Style.NewEdges(borderFrame, "BORDER") },
        elements = {}, layout = {}, ctx = {}, spells = {}, spellCount = 0, seen = {},
    }, InstanceMT)
end

-- ---------------------------------------------------------------------------
-- Watching
-- ---------------------------------------------------------------------------

local function unwatch(inst)
    local unit = inst.unit
    if not unit then return end
    local set = byUnit[unit]
    if set then set[inst] = nil end
    inst.unit = nil
    NS.Ticker.Unwatch(unit)
end

--- Watch `unit`. Answers false when the instance already watched it. The watch reads the unit at
--- once, so the instance hears its first RANGE_UPDATED inside this call.
local function watch(inst, unit)
    if inst.unit == unit then return false end
    unwatch(inst)
    inst.unit = unit
    local set = byUnit[unit]
    if not set then
        set = {}
        byUnit[unit] = set
    end
    set[inst] = true
    NS.Ticker.Watch(unit)
    return true
end

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------

--- The anchors place it (modules/Anchors.lua); without them, at its stored point on UIParent.
local function place(inst, c)
    if NS.Anchors and NS.Anchors.Apply then return NS.Anchors.Apply(inst, c) end
    local a, root = c.anchor, inst.frame
    root:ClearAllPoints()
    root:SetPoint(a.point or "CENTER", UIParent, a.relPoint or "CENTER", tonumber(a.x) or 0, tonumber(a.y) or 0)
end

--- Show or hide the root, and tell the anchors when that changed.
local function setShown(inst, show)
    if show == inst.shown then return end
    inst.shown = show
    if show then inst.frame:Show() else inst.frame:Hide() end
    local A = NS.Anchors
    if A and A.ShownChanged then A.ShownChanged(inst) end
end

local function applyFrame(inst, c)
    local root, lay = inst.frame, c.layout
    root:SetFrameStrata(STRATA[c.anchor.strata] and c.anchor.strata or LAYERS.STRATA.HUD)
    inst.appliedScale = tonumber(lay.scale) or 1
    root:SetScale(inst.appliedScale)
    root:SetAlpha(tonumber(lay.alpha) or 1)
    Style.Border(inst.border, c.frame.border)
    inst.background:SetShown(c.frame.background.enabled and true or false)
    place(inst, c)
end

--- Build the enabled elements this frame does not have yet, style them, and hide the rest.
local function applyElements(inst, c)
    for name, mod in pairs(ELEMENT) do
        local cfg, el = c.elements[name], inst.elements[name]
        if type(cfg) == "table" and cfg.enabled then
            if not el then
                el = mod.Build(inst)
                inst.elements[name] = el
            end
            mod.Style(el, cfg, c)
            el.on = true
            el.frame:Show()
        elseif el then
            el.on = false
            el.frame:Hide()
        end
    end
end

--- Forget what was drawn, so the next render paints everything.
function Instance:Invalidate()
    self.bandIndex, self.setId, self.layoutDirty = nil, nil, true
end

--- Draw the last triple again (or the unit's current one).
function Instance:Rerender()
    if self.state == nil then return self:Update(NS.Range.Get(self.unit)) end
    return self:Update(self.state, self.lo, self.hi)
end

--- Take container `c`'s settings (id `id`) and draw from them. A plate instance watches its plate's
--- token, every other its container's unit.
function Instance:Apply(id, c)
    self.id, self.container = id, c
    self.applying = true
    applyFrame(self, c)
    applyElements(self, c)
    self.applying = nil
    self:Invalidate()
    if not watch(self, self.plateToken or c.unit) then self:Rerender() end
end

--- The anchor's say on whether this instance may show: hidden while the frame or plate it belongs on
--- is missing. Shown again, it draws its unit's range from scratch (outside an apply, which draws on
--- its own).
function Instance:SetAnchorHidden(hidden)
    hidden = hidden and true or false
    if (self.anchorHidden or false) == hidden then return end
    self.anchorHidden = hidden
    if hidden then return setShown(self, false) end
    if self.applying or not self.container then return end
    self:Invalidate()
    self:Rerender()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

--- The enabled, sized elements in `elements.order`, each once, into inst.layout's cells.
local function collect(inst, c)
    local cells, seen, n = inst.layout, inst.seen, 0
    for k in pairs(seen) do seen[k] = nil end
    for _, name in ipairs(c.elements.order or {}) do
        local el = inst.elements[name]
        if not seen[name] and el and el.on and el.w > 0 then
            seen[name] = true
            n = n + 1
            local cell = cells[n] or {}
            cells[n] = cell
            cell.name, cell.el, cell.w, cell.h = name, el, el.w, el.h
        end
    end
    for i = #cells, n + 1, -1 do cells[i] = nil end
    return cells, n
end

--- Place the cells along the main axis from the padding, centered across it, and size the root.
function Instance:Layout()
    self.layoutDirty = false
    local lay = self.container.layout
    local pad, gap = tonumber(lay.padding) or 0, tonumber(lay.spacing) or 0
    local row = lay.direction ~= "column"
    local cells, n = collect(self, self.container)
    local cross = 0
    for i = 1, n do cross = math.max(cross, row and cells[i].h or cells[i].w) end
    local pos = pad
    for i = 1, n do
        local cell = cells[i]
        if row then
            cell.x, cell.y, pos = pos, pad + (cross - cell.h) / 2, pos + cell.w + gap
        else
            cell.x, cell.y, pos = pad + (cross - cell.w) / 2, pos, pos + cell.h + gap
        end
        local f = cell.el.frame
        f:SetSize(cell.w, cell.h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", self.frame, "TOPLEFT", cell.x, -cell.y)
    end
    local main = n > 0 and (pos - gap + pad) or pad * 2
    if row then self.width, self.height = main, cross + pad * 2 else self.width, self.height = cross + pad * 2, main end
    self.frame:SetSize(self.width, self.height)
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Every color: the border, the fill, then each element. Answers whether a cell's width moved.
function Instance:Paint(ctx)
    local c = self.container
    local bd, bg = c.frame.border, c.frame.background
    if bd.enabled then Style.PaintBorder(self.border, Style.Color(bd.colorMode, bd.color, ctx, "frameColor")) end
    if bg.enabled then
        local r, g, b, a = Style.Color(bg.colorMode, bg.color, ctx, "frameColor")
        if bg.colorMode == "band" then a = a * (tonumber(bg.bandAlpha) or 0.15) end
        self.background:SetColorTexture(r, g, b, a)
    end
    local moved = false
    for name, mod in pairs(ELEMENT) do
        local el = self.elements[name]
        if el and el.on and mod.Paint(el, c.elements[name], ctx) then moved = true end
    end
    return moved
end

--- The band to draw and the set it is read from, into ctx. Answers whether it differs from the last.
local function resolveBand(inst, state, lo, hi)
    local B = NS.BandSets
    local setId = B.ForUnit(inst.container, inst.unit)
    local band = B.Resolve(setId, state, lo, hi) or "none"
    if band == inst.bandIndex and setId == inst.setId then return false end
    local ctx, set = inst.ctx, B.Get(setId)
    ctx.set, ctx.band = set, band
    ctx.row = type(band) == "number" and set and set.bands[band] or nil
    ctx.unknownLabel = set and set.unknown and set.unknown.label
    inst.bandIndex, inst.setId = band, setId
    return true
end

--- Show or hide for the anchor's say and the unit's presence; answers whether to draw on.
local function present(inst, state)
    local show = not inst.anchorHidden and (state ~= "none" or not inst.container.visibility.hideNoUnit)
    setShown(inst, show)
    return show
end

function Instance:Render(state, lo, hi, spellResults)
    local c = self.container
    if not c then return end
    self.state, self.lo, self.hi = state, lo, hi
    if not present(self, state) then return end
    local ctx = self.ctx
    ctx.state, ctx.lo, ctx.hi, ctx.spells = state, lo, hi, spellResults or NO_SPELLS
    ctx.unit = self.unit
    local moved = resolveBand(self, state, lo, hi) and self:Paint(ctx) or false
    for name, mod in pairs(ELEMENT) do
        local el = self.elements[name]
        if el and el.on and mod.Update(el, c.elements[name], ctx) then moved = true end
    end
    if moved or self.layoutDirty then self:Layout() end
end

--- The spell list this instance asks for `state`, or nil when it asks none.
local function spellList(inst, state)
    local c = inst.container
    local sp = c and c.elements.spells
    if sp and sp.enabled and state ~= nil and state ~= "none" and type(sp.list) == "table" then return sp.list end
    return nil
end

--- Ask each spell chip's answer for this unit, then render.
function Instance:Update(state, lo, hi)
    local res, n, list = self.spells, 0, spellList(self, state)
    if list then
        for i, id in ipairs(list) do
            res[i] = NS.Range.InSpellRange(id, self.unit)
            n = i
        end
    end
    for i = n + 1, self.spellCount do res[i] = nil end
    self.spellCount = n
    return self:Render(state, lo, hi, res)
end

--- The unit was read again and its triple did not move: ask the chips again, and render only when
--- an answer moved. Answers whether it rendered.
function Instance:PollSpells()
    local list = spellList(self, self.state)
    if not list then return false end
    local res = self.spells
    for i, id in ipairs(list) do
        if NS.Range.InSpellRange(id, self.unit) ~= res[i] then
            self:Update(self.state, self.lo, self.hi)
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The pool
-- ---------------------------------------------------------------------------

--- An instance's teardown before it is parked: no watch, no container, nothing drawn remembered.
local function park(inst)
    if NS.Anchors and NS.Anchors.Detach then NS.Anchors.Detach(inst) end
    unwatch(inst)
    inst.key, inst.id, inst.container, inst.pool, inst.plateToken = nil, nil, nil, nil, nil
    inst.state, inst.lo, inst.hi, inst.shown, inst.anchorHidden = nil, nil, nil, nil, nil
    inst.bandIndex, inst.setId = nil, nil
    inst.frame:ClearAllPoints()
end

--- Park the one object filed under `key` in `from`, as Pool.ReleaseAllKeyed parks each.
local function releaseKeyed(from, key)
    local o = from.active[key]
    if not o then return false end
    park(o)
    o:Hide()
    from.active[key] = nil
    from.free[#from.free + 1] = o
    return true
end

function Instance:Release()
    local from = self.pool
    if self.key == nil or not from or from.active[self.key] ~= self then return false end
    return releaseKeyed(from, self.key)
end

--- The live instance of container `id`, applied from its settings now. Nil for an unknown id and for
--- a `nameplates` container (its instances are per plate: AcquirePlate).
function Container.Acquire(id)
    local c = NS.CM.Get(id)
    if not c or c.unit == "nameplates" then return nil end
    local inst = Pool.AcquireKeyed(pool, id, newInstance)
    inst.key, inst.pool = id, pool
    inst:Apply(id, c)
    return inst
end

function Container.Get(id) return pool.active[id] end

-- ---------------------------------------------------------------------------
-- Per-plate instances (a `nameplates` container's)
-- ---------------------------------------------------------------------------

local function plateKey(id, token) return tostring(id) .. "|" .. token end

--- The instance of `nameplates` container `id` on the plate behind `token`, applied from its settings
--- now (a live one is re-applied). Nil for any other container or a token that is not a string.
function Container.AcquirePlate(id, token)
    local c = NS.CM.Get(id)
    if not (c and c.unit == "nameplates" and type(token) == "string") then return nil end
    local key = plateKey(id, token)
    local inst = Pool.AcquireKeyed(platePool, key, newInstance)
    inst.key, inst.pool, inst.plateToken = key, platePool, token
    inst:Apply(id, c)
    return inst
end

function Container.GetPlate(id, token)
    if type(token) ~= "string" then return nil end
    return platePool.active[plateKey(id, token)]
end

--- Park the instance of container `id` on `token`. Answers whether there was one.
function Container.ReleasePlate(id, token)
    if type(token) ~= "string" then return false end
    return releaseKeyed(platePool, plateKey(id, token))
end

--- fn(inst, id, token) for every live plate instance.
function Container.ForEachPlate(fn)
    for _, inst in pairs(platePool.active) do fn(inst, inst.id, inst.plateToken) end
end

function Container.ForEach(fn)
    for _, inst in pairs(pool.active) do fn(inst) end
end

local function wanted(c)
    return c ~= nil and c.enabled and c.unit ~= "nameplates"
end

local function wantsPlates(c)
    return c ~= nil and c.enabled and c.unit == "nameplates"
end

local stale = {}

--- Park every instance in `from` whose container `keep` turns down.
local function releaseStale(from, keep)
    local n = 0
    for key, inst in pairs(from.active) do
        if not keep(NS.CM.Get(inst.id)) then
            n = n + 1
            stale[n] = key
        end
    end
    for i = 1, n do
        releaseKeyed(from, stale[i])
        stale[i] = nil
    end
end

--- Every enabled container drawn, every other one parked; then the plate anchors give each enabled
--- `nameplates` container its per-plate instances (NS.Plates.SyncAll).
function Container.Sync()
    if NS.IsStoodDown() then return end
    releaseStale(pool, wanted)
    releaseStale(platePool, wantsPlates)
    for _, id in ipairs(NS.CM.List()) do
        if wanted(NS.CM.Get(id)) then Container.Acquire(id) end
    end
    if NS.Plates and NS.Plates.SyncAll then NS.Plates.SyncAll() end
end

local function repaint(inst)
    inst:Invalidate()
    inst:Rerender()
end

--- A band set changed: every instance paints again from its last triple.
function Container.Repaint()
    for _, inst in pairs(pool.active) do repaint(inst) end
    for _, inst in pairs(platePool.active) do repaint(inst) end
end

--- A different unit sits behind `unit`: its instances forget what they drew. The caller then has the
--- ticker send the token's triple (NS.Ticker.Changed), which renders them in full.
function Container.UnitChanged(unit)
    local set = byUnit[unit]
    if not set then return end
    for inst in pairs(set) do inst:Invalidate() end
end

--- The stand-down (core/LifecycleSetup.lua): every instance parked and hidden, every watch dropped.
function Container.StandDown()
    Pool.ReleaseAllKeyed(pool, park)
    Pool.ReleaseAllKeyed(platePool, park)
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

--- RANGE_UPDATED: the instances on that unit, and only those (bucket container.render).
local function onRangeUpdated(_, unit, state, lo, hi)
    local set = byUnit[unit]
    if not set then return end
    local t0 = Perf.on and debugprofilestop()
    for inst in pairs(set) do inst:Update(state, lo, hi) end
    if t0 then Perf.Note("container.render", debugprofilestop() - t0, NS.Range.PerfParent()) end
end

--- A steady read (NS.Ticker.OnSteady): the instances on that unit re-ask their spell chips. One that
--- renders is recorded in container.render like a RANGE_UPDATED render; one with no chips costs a
--- field read.
local function onSteady(unit)
    local set = byUnit[unit]
    if not set then return end
    local t0 = Perf.on and debugprofilestop()
    local rendered = false
    for inst in pairs(set) do
        if inst:PollSpells() then rendered = true end
    end
    if t0 and rendered then Perf.Note("container.render", debugprofilestop() - t0, NS.Range.PerfParent()) end
end

local target = NS.NewBusTarget()
if target then
    target:RegisterMessage(NS.MSG.RANGE_UPDATED, onRangeUpdated)
    target:RegisterMessage(NS.MSG.CONTAINERS_CHANGED, function() Container.Sync() end)
    target:RegisterMessage(NS.MSG.BANDSETS_CHANGED, function() Container.Repaint() end)
end

NS.Ticker.OnSteady(onSteady)

-- The HUD face follows the skin: a skin change asks for an apply of every container, which
-- ContainerManager coalesces to the next frame and holds through combat.
NS.Skin.OnLooksChanged(function() NS.CM.RequestApply() end)

-- Suite seams (tests/test_container_render.lua).
function Container.__counts() return Pool.CountsKeyed(pool) end
function Container.__plateCounts() return Pool.CountsKeyed(platePool) end
function Container.__reset()
    Pool.ReleaseAllKeyed(pool, park)
    Pool.ReleaseAllKeyed(platePool, park)
    pool, platePool = Pool.NewKeyed(), Pool.NewKeyed()
    for unit in pairs(byUnit) do byUnit[unit] = nil end
end
