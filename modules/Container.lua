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
--   inst:DockStrips()                    dock the preview strips again, beyond a drag handle built
--                                        after them (modules/Anchors_Screen.lua, on the first unlock)
--   inst:RefreshStrips()                 the root came onto or off a nameplate: the strips follow
--                                        (modules/Anchors_Nameplate.lua)
--   NS.Container.SetPreview(kind|nil)    Test mode ("test") or Sim mode ("sim") draws, or neither
--                                        (modules/Preview.lua is its one caller)
--   NS.Container.RefreshVisibility()     ask every instance's visibility again (the combat edge,
--                                        the General visibility and Master opacity rows)
--   NS.Container.RefreshLock()           the `locked` setting moved: unlocked shows every container
--   NS.Container.ShowsAll() -> boolean   a preview runs, or the displays are unlocked out of combat
--   NS.Container.Unlocked() -> boolean   the displays are unlocked out of combat (every one shows,
--                                        every one wears its drag strip, modules/Anchors*.lua)
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
--
-- SHOWN OR HIDDEN is the anchor's say first (SetAnchorHidden), then NS.Visibility.Evaluate
-- (modules/Visibility.lua: the Master controls' General visibility, the container's combat, reaction
-- and no-unit rules), whose opacity multiplies the layout's. Both are asked on every render, and again
-- over every instance on the combat edge and on a master row's write (RefreshVisibility). A render of
-- a hidden instance stops there, so it paints nothing and plays nothing.
--
-- THE PREVIEW MODES (modules/Preview.lua) draw through this same path, from NS.Range's fake source.
-- While one runs every instance shows whatever its visibility says, an instance whose anchor hides it
-- (a missing frame, no plate) is placed at its screen point instead (NS.Anchors.Screen.Place), and a
-- `nameplates` container gets one stand-in instance of its own (the main pool, keyed by its id) so it
-- has a placeholder with no plate on screen; the stand-in goes when the preview ends. Each instance
-- wears LibKa0s-Widgets' TestStrip while a preview runs (preview-mode: amber for Test mode, cyan for
-- Sim mode), docked on its top edge (`dock = "hud"`), built on first use and kept with the frame. A
-- preview never runs in combat (refused in it, ended by it), so the stand-ins are built out of combat.
--
-- A ROOT ON A NAMEPLATE CANNOT BE MEASURED. The client refuses GetTop and its kin on a region
-- anchored to a nameplate ("Can't measure restricted regions"), and the HUD dock measures its target
-- (to flip under the display near the screen's top) on every show and resize, through hooks no
-- pcall here covers. So the dock's target is not the root but `inst.stripHost`, a child laid over
-- it and parked on UIParent's center while the root sits on a plate (`inst.anchorPlate`, which the
-- nameplate anchors keep true to the root's points). On a plate the instance wears a second strip of
-- each kind instead, undocked, anchored on the root's top edge and never measured (it does not flip).
-- `inst.strips` is the set worn where the root sits now.
--
-- WHILE ITS DRAG STRIP SHOWS TAGGED, a display wears no TestStrip: the drag strip's TEST or SIM tag
-- is its preview marker (preview-mode, *Where the strip sits*, v2.114.0; NS.Anchors.Screen.Tagged).
-- The TestStrip shows again the moment the drag strip hides while the preview still draws.
--
-- UNLOCKED SHOWS EVERY CONTAINER TOO, out of combat, so each can be found and placed: the same rule
-- as a preview (no visibility rule asked, a missing frame or plate at its screen point, a
-- `nameplates` container through its stand-in), but on the live range. A container whose unit is not
-- there draws the preview's placeholder triple (NS.Preview.PLACEHOLDER) so it is not an empty box; it
-- keeps "none" as its state, so the combat edge, which ends this (as it ends a preview), hides it on
-- its own rules, and a placeholder plays no band sound. No preview strip is worn.
--
-- BAND SOUNDS (modules/Sounds.lua) hear every shown render's band and every steady read of a shown
-- instance's unit; a unit change forgets the instance's sound state (UnitChanged), as does a preview
-- starting or ending.

NS.Container = NS.Container or {}
local Container = NS.Container

local Perf = NS.Perf
local LAYERS = NS.Constants.LAYERS
local Style = NS.Style
local Pool = NS.Pool
local E = NS.Elements

local ELEMENT = { number = E.Number, text = E.Text, indicator = E.Indicator, spells = E.Spells }

local KW = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
local L = NS.L

local pool = Pool.NewKeyed()
local platePool = Pool.NewKeyed()   -- the per-plate instances, keyed "<id>|<token>"
local byUnit = {}   -- [unit] = { [inst] = true }: the RANGE_UPDATED fan-out
local NO_SPELLS = {}
local preview      -- nil, "test" or "sim": the preview drawing (SetPreview)
local unlockShow = false   -- unlocked and out of combat: every container shows (RefreshLock)

--- Whether every container shows whatever its rules say: a preview runs, or the displays are
--- unlocked out of combat.
local function showsAll() return preview ~= nil or unlockShow end
local STRIP_KINDS = { "test", "sim" }

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

local nextSlot = 0   -- the last per-instance level slot handed out (1..LAYERS.LEVEL.SLOTS, cycling)

--- One pooled instance: the root at its own base level (a pooled instance keeps it), then the fill,
--- the border and the overlay as levels over it (core/Constants.lua LAYERS).
local function newInstance()
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetFrameStrata(LAYERS.STRATA.HUD)
    local LV = LAYERS.LEVEL
    nextSlot = nextSlot % LV.SLOTS + 1
    Style.Stack(root, UIParent, LV.BASE + nextSlot * LV.STRIDE)
    local fill = layer(root, LAYERS.LEVEL.FILL)
    local bg = fill:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(fill)
    local borderFrame = layer(root, LAYERS.LEVEL.BORDER)
    -- The preview strips' dock target: over the root, parked while the root sits on a plate (header).
    local host = CreateFrame("Frame", nil, root)
    host:SetAllPoints(root)
    return setmetatable({
        frame = root, fill = fill, background = bg, overlay = layer(root, LAYERS.LEVEL.OVERLAY),
        stripHost = host, hostParked = false,
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

--- The root's opacity: the layout's, times the visibility's (`a`). Set only when it moved.
local function setAlpha(inst, a)
    local v = (inst.baseAlpha or 1) * (a or 1)
    if v == inst.alpha then return end
    inst.alpha = v
    inst.frame:SetAlpha(v)
end

local function applyFrame(inst, c)
    local root, lay = inst.frame, c.layout
    -- Only the values the Frame strata row offers (settings/Containers.lua, read at call time): a
    -- hand-edited DIALOG or higher is no HUD tier and falls back (frame-layering-§1).
    local V = NS.ContainerValues
    local strata = c.anchor.strata
    root:SetFrameStrata(V and V.STRATA and V.STRATA[strata] and strata or LAYERS.STRATA.HUD)
    -- The container's own scale inside the Master controls' Master scale.
    inst.appliedScale = (tonumber(lay.scale) or 1) * (tonumber(NS.GetSetting("scale")) or 1)
    root:SetScale(inst.appliedScale)
    inst.baseAlpha, inst.alpha = tonumber(lay.alpha) or 1, nil
    root:SetAlpha(inst.baseAlpha)
    Style.Border(inst.border, c.frame.border)
    inst.background:SetShown(c.frame.background.enabled and true or false)
    place(inst, c)
end

--- Build the enabled elements this frame does not have yet, style them, and hide the rest.
local function applyElements(inst, c)
    -- The chips this character shows, resolved once per apply (NS.CM.SpellChips): the stored list,
    -- else the logged-in class's seeds. The per-tick reads use this, never the resolver.
    inst.chipList = NS.CM.SpellChips(c)
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
    if hidden and showsAll() and self.container then
        -- A preview shows it anyway, at its screen point (the frame or plate it belongs on is missing).
        return NS.Anchors.Screen.Place(self, self.container)
    end
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

--- The dock of this instance's docked strips: on the display's top edge (through the strip host,
--- see the header), stacked beyond its drag handle while that shows (preview-mode, *Where the strip
--- sits*).
local function dockSpec(inst)
    return { dock = "hud", target = inst.stripHost, clear = inst.dragHandle or nil }
end

local PLATE_STRIP_LEVEL = 5   -- the HUD dock's chrome band: this many levels over the display

--- A new preview strip of `kind`: docked, or (`onPlate`) anchored on the root's top edge by hand,
--- taking no mouse, a chrome band over the display. False without the library.
local function newStrip(inst, kind, onPlate)
    if not (KW and KW.TestStrip) then return false end
    local root = inst.frame
    local opts = { text = kind == "sim" and L["SIM"] or L["TEST"], icon = NS.Icon("info"), kind = kind,
                   owner = NS.name }
    if not onPlate then opts.dock, opts.target, opts.clear = "hud", inst.stripHost, inst.dragHandle or nil end
    local ok, s = pcall(KW.TestStrip, root, opts)
    if not (ok and s) then return false end
    if onPlate then
        s:EnableMouse(false)
        s:ClearAllPoints()
        s:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 0)
        s:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", 0, 0)
        s:SetFrameStrata(LAYERS.STRATA.HUD)
        local okLevel, level = pcall(root.GetFrameLevel, root)
        if okLevel and type(level) == "number" then s:SetFrameLevel(level + PLATE_STRIP_LEVEL) end
    end
    return s
end

--- The strip host over the root, or parked on UIParent's center while the root sits on a plate.
local function syncHost(inst)
    local parked = inst.anchorPlate ~= nil
    if inst.hostParked == parked then return end
    inst.hostParked = parked
    local host = inst.stripHost
    host:ClearAllPoints()
    if parked then
        host:SetSize(1, 1)
        host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    else
        host:SetAllPoints(inst.frame)
    end
end

--- The drag handle was built after the strips were (modules/Anchors_Screen.lua builds it on the
--- first unlock): dock every docked strip again, so each stacks beyond the handle rather than over it.
function Instance:DockStrips()
    local docked = self.stripSets and self.stripSets.docked
    if not (docked and self.dragHandle and KW and KW.DockTestStrip) then return end
    for _, s in pairs(docked) do
        if s then pcall(KW.DockTestStrip, s, dockSpec(self)) end
    end
end

--- Show the running preview's strip of the set worn where the root sits (built on first use) and
--- hide every other strip (every strip with no preview, and every one while the drag strip shows
--- tagged: the header).
local function showStrips(inst)
    syncHost(inst)
    if not preview and not inst.stripSets then return end
    local marker = preview ~= nil and not NS.Anchors.Screen.Tagged(inst)
    inst.stripSets = inst.stripSets or { docked = {}, plate = {} }
    local onPlate = inst.anchorPlate ~= nil
    local set = onPlate and inst.stripSets.plate or inst.stripSets.docked
    local other = onPlate and inst.stripSets.docked or inst.stripSets.plate
    inst.strips = set
    for _, s in pairs(other) do
        if s then s:Hide() end
    end
    for _, kind in ipairs(STRIP_KINDS) do
        local s = set[kind]
        if s == nil and preview == kind then
            s = newStrip(inst, kind, onPlate)
            set[kind] = s
        end
        if s then
            local on = marker and preview == kind
            s:SetShown(on)
            if on and not onPlate and s.Place then pcall(s.Place, s) end
        end
    end
end

function Instance:RefreshStrips() showStrips(self) end

--- Show or hide for the anchor's say and the visibility rules (or the preview); answers whether to
--- draw on.
local function present(inst, state)
    if showsAll() then
        if inst.anchorHidden then NS.Anchors.Screen.Place(inst, inst.container) end
        setShown(inst, true)
        setAlpha(inst, 1)
        return true
    end
    local show, alpha = NS.Visibility.Evaluate(inst.container, inst.unit, state)
    show = show and not inst.anchorHidden
    setShown(inst, show)
    if show then setAlpha(inst, alpha) end
    return show
end

function Instance:Render(state, lo, hi, spellResults)
    local c = self.container
    if not c then return end
    self.state, self.lo, self.hi = state, lo, hi
    if not present(self, state) then return end
    -- Unlocked with no unit: the placeholder, so the display has something to show (see the header).
    local stand = unlockShow and not preview and (state == nil or state == "none")
    if stand then
        local PH = NS.Preview.PLACEHOLDER
        state, lo, hi = PH[1], PH[2], PH[3]
    end
    local ctx = self.ctx
    ctx.state, ctx.lo, ctx.hi, ctx.spells = state, lo, hi, spellResults or NO_SPELLS
    ctx.unit = self.unit
    local moved = resolveBand(self, state, lo, hi) and self:Paint(ctx) or false
    if c.sounds and c.sounds.enabled and not stand then NS.Sounds.OnBand(self, self.bandIndex, GetTime()) end
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
    if sp and sp.enabled and state ~= nil and state ~= "none" then return inst.chipList end
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
    inst.bandIndex, inst.setId, inst.sound, inst.alpha = nil, nil, nil, nil
    for _, set in pairs(inst.stripSets or {}) do
        for _, s in pairs(set) do
            if s then s:Hide() end
        end
    end
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
--- a `nameplates` container (its instances are per plate: AcquirePlate) unless every container
--- shows (a preview, or unlocked), when it gets its one stand-in.
function Container.Acquire(id)
    local c = NS.CM.Get(id)
    if not c or (c.unit == "nameplates" and not showsAll()) then return nil end
    local inst = Pool.AcquireKeyed(pool, id, newInstance)
    inst.key, inst.pool = id, pool
    inst:Apply(id, c)
    showStrips(inst)
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
    showStrips(inst)
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
    return c ~= nil and c.enabled and (c.unit ~= "nameplates" or showsAll())
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
--- Whether the displays are unlocked out of combat, read now.
local function unlockedNow()
    return NS.GetSetting("locked") == false and not NS.Visibility.InCombat()
end

function Container.Sync()
    if NS.IsStoodDown() then return end
    unlockShow = unlockedNow()
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
    for inst in pairs(set) do
        inst:Invalidate()
        NS.Sounds.Reset(inst)
    end
end

--- Ask one instance's visibility again from its last triple; one newly shown draws in full.
local function revisit(inst)
    if not inst.container or inst.state == nil then return end
    local was = inst.shown
    if present(inst, inst.state) and not was then repaint(inst) end
end

local restage   -- below: every instance drawn again under the show-all rule as it is now

function Container.RefreshVisibility()
    -- The combat edge ends (and the leave edge brings back) the unlocked show-all.
    if unlockedNow() ~= unlockShow then return Container.RefreshLock() end
    for _, inst in pairs(pool.active) do revisit(inst) end
    for _, inst in pairs(platePool.active) do revisit(inst) end
end

--- The `locked` setting moved (settings/General.lua), or the combat edge crossed it: every container
--- shows while unlocked out of combat, and goes back to its own rules otherwise.
function Container.RefreshLock()
    local on = unlockedNow()
    if on == unlockShow then return end
    unlockShow = on
    NS.Debug("Containers", on and "unlocked: every container shows" or "show-all ended: own rules")
    -- A cursor or own-plate container waits at its screen point while unlocked (modules/Anchors.lua).
    for _, inst in pairs(pool.active) do NS.Anchors.Refresh(inst) end
    restage()
end

--- Draw one instance again from the current source: everything forgotten, its unit read now.
local function redraw(inst)
    inst:Invalidate()
    NS.Sounds.Reset(inst)
    showStrips(inst)
    if inst.unit then inst:Update(NS.Range.Get(inst.unit)) end
end

--- Test mode ("test"), Sim mode ("sim") or neither (nil) draws now. The caller (modules/Preview.lua)
--- has set NS.Range's source first, so each redraw reads the preview's range. Starting one gives each
--- enabled `nameplates` container its stand-in; ending one parks them.
--- Every instance drawn again under the show-all rule as it is now: a `nameplates` stand-in made
--- while every container shows, parked once none does.
restage = function()
    if not NS.IsStoodDown() then
        releaseStale(pool, wanted)
        if showsAll() then
            for _, id in ipairs(NS.CM.List()) do
                local c = NS.CM.Get(id)
                if wantsPlates(c) and not pool.active[id] then Container.Acquire(id) end
            end
        end
    end
    for _, inst in pairs(pool.active) do redraw(inst) end
    for _, inst in pairs(platePool.active) do redraw(inst) end
    -- The drag strips: shown for every container while unlocked, and the TEST tag in their labels.
    NS.Anchors.RefreshLock()
end

function Container.SetPreview(kind)
    preview = kind
    restage()
end

function Container.PreviewKind() return preview end
function Container.ShowsAll() return showsAll() end
function Container.Unlocked() return unlockShow end

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
    local rendered, now = false, nil
    for inst in pairs(set) do
        if inst:PollSpells() then rendered = true end
        local snd = inst.shown and inst.container and inst.container.sounds
        if snd and snd.enabled then
            now = now or GetTime()
            NS.Sounds.OnBand(inst, inst.bandIndex, now)
        end
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
    preview, unlockShow = nil, false
    for unit in pairs(byUnit) do byUnit[unit] = nil end
end
