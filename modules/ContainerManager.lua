local _, NS = ...
-- modules/ContainerManager.lua — the container registry (design spec 5.2, 5.3): the ONE runtime
-- writer of profile.containers, containerOrder, nextContainerId and the first-run sentinel seeded
-- (architecture-§5; the other writer is core/Database.lua's load pass) and the sole sender of
-- NS.MSG.CONTAINERS_CHANGED.
--
--   NS.CM.Create(unit?, opts?) -> id         unit defaults to "target"; opts merge over the template,
--                                            never over the unit (the positional one is the checked one)
--   NS.CM.Delete(id) -> boolean, Duplicate(id) -> id, Rename(id, name) -> boolean
--   NS.CM.UniqueName(base, exceptId?) -> name    "Target", "Target 2", ... (case-insensitive)
--   NS.CM.CopySettings(fromId, toId, sections?) -> boolean   never identity or placement
--   NS.CM.Snapshot() -> snap, RestoreSnapshot(snap) -> boolean   the registry whole, ids included
--   NS.CM.List() -> { id, ... }, Get(id) -> container
--   NS.CM.SpellChips(c) -> { spellID, ... }  the stored chip list, else the logged-in class's seeds
--   NS.CM.RequestApply()                     coalesced to the next frame, deferred in combat
--   NS.CM.SetPosition(id, point, relPoint, x, y) -> boolean   a drag's result (modules/Anchors_Screen)
--   NS.CM.ResetPosition(id) -> boolean       back to the new-container point (Reset position)
--   NS.CM.SetField(id, field, value) -> boolean   one setting of one container, by its dotted field
--                                            (the settings pages' and `/rm set container.<field>`'s writer)
--   NS.CM.MarkSeeded()                       the first-run preset picker has shown on this profile
--                                            (profile.seeded; NS.Presets.MarkPickerSeen's write)
--   NS.CM.IsElementOrder(v) -> boolean       an array naming each of the four elements once: the only
--                                            `elements.order` SetField stores (the drag list's, the CLI's)
--
-- APPLYING IS COALESCED AND DEFERRED. Every write above asks for an apply; the request arms one
-- zero-delay C_Timer, so a whole preset or a slider drag announces CONTAINERS_CHANGED once, on the
-- next frame. A flush under combat lockdown waits (a container anchored to a unit frame must not be
-- re-anchored then, design spec 3) and runs on PLAYER_REGEN_ENABLED (core/RangeMaster.lua's
-- OnCombatChanged calls FlushPending). The renderer (plan Task 5) and the settings pages listen.
--
-- A STOOD-DOWN ADDON ARMS NO TIMER (slash-commands-§7). A write while stood down still lands in the
-- registry; nothing is lost, because the stand-up asks for one apply of everything as it is then.
--
-- A SNAPSHOT IS BOTH REGISTRIES. A preset (modules/Presets.lua) may add the Healer band set and an
-- out-of-range sound, so its Undo must put the band sets back too. That half is the band-set
-- registry's own writer's (NS.BandSets.Snapshot / RestoreSnapshot), so each registry keeps one writer.

NS.CM = NS.CM or {}
local CM = NS.CM

local L = NS.L

--- The units a container may watch (design spec 2), and the name a new one takes from its unit.
local UNIT_NAME = {
    target = L["Target"], focus = L["Focus"], pet = L["Pet"], mouseover = L["Mouseover"],
    nameplates = L["Nameplates"],
}
CM.UNITS = { "target", "focus", "pet", "mouseover", "nameplates" }

--- What CopySettings copies when no list is given: how a container looks and behaves. Never its
--- identity (name, enabled, unit) or its placement (anchor), which are what make it this container.
--- The caption (`label`) is copied whole: an empty text still reads each container's own name.
CM.COPY_SECTIONS = { "bandSet", "bandSetFriendly", "layout", "frame", "label", "elements", "visibility",
    "sounds", "nameplate" }
local COPYABLE = {}
for _, key in ipairs(CM.COPY_SECTIONS) do COPYABLE[key] = true end

local pending = false   -- an apply is owed
local flushTimer        -- the one coalescing timer's handle, so a flush or a stand-down can cancel it
local heldTraced = false -- the combat hold was traced once (debug-logging-§9, quiet steady state)

local function profile() return NS.db and NS.db.profile end
local function copy(v) return NS.Database.DeepCopy(v) end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- The container ids in order, as a new array.
function CM.List()
    local p, out = profile(), {}
    for i, id in ipairs(p and p.containerOrder or {}) do out[i] = id end
    return out
end

--- The stored container `id` (the live table), or nil.
function CM.Get(id)
    local p = profile()
    return p and p.containers and p.containers[id]
end

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------

--- Announce now unless combat holds it. Answers whether CONTAINERS_CHANGED went out.
function CM.FlushPending(edge)
    if flushTimer then
        flushTimer:Cancel()
        flushTimer = nil
    end
    if not pending or NS.IsStoodDown() then return false end
    if InCombatLockdown() then
        if not heldTraced then
            heldTraced = true
            NS.Debug("Containers", "apply deferred until combat ends (edge %s)", edge or "frame")
        end
        return false
    end
    pending, heldTraced = false, false
    NS.bus:SendMessage(NS.MSG.CONTAINERS_CHANGED)
    return true
end

local function onNextFrame()
    flushTimer = nil
    CM.FlushPending()
end

--- Ask for the containers to be re-applied, on the next frame.
function CM.RequestApply()
    pending = true
    if flushTimer or NS.IsStoodDown() then return end
    flushTimer = C_Timer.NewTimer(0, onNextFrame)
end

--- The stand-down (core/LifecycleSetup.lua): the coalescing timer goes; what is owed stays owed.
function CM.StandDown()
    if flushTimer then
        flushTimer:Cancel()
        flushTimer = nil
    end
end

--- The stand-up: one apply of every container as the settings are now.
function CM.StandUp()
    CM.RequestApply()
end

-- Suite seams (tests/test_container_manager.lua, tests/test_presets.lua).
function CM.__flushTimer() return flushTimer end
function CM.__pending() return pending end
function CM.__reset()
    CM.StandDown()
    pending, heldTraced = false, false
end

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

--- A trimmed string, or "" for anything else.
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:match("^%s*(.-)%s*$"))
end

--- A name no other container uses: `base`, else `base 2`, `base 3`, ... Names that differ only in
--- case are taken, because `/rm select <name>` (plan Task 8) matches without case. `exceptId`'s own
--- name is free (a rename to itself).
function CM.UniqueName(base, exceptId)
    base = trim(base)
    if base == "" then base = L["Container"] end
    local taken, p = {}, profile()
    for id, c in pairs(p and p.containers or {}) do
        if id ~= exceptId and type(c.name) == "string" then taken[c.name:lower()] = true end
    end
    if not taken[base:lower()] then return base end
    local n = 2
    while taken[("%s %d"):format(base, n):lower()] do n = n + 1 end
    return ("%s %d"):format(base, n)
end

-- ---------------------------------------------------------------------------
-- Writing (the registry's one runtime writer)
-- ---------------------------------------------------------------------------

--- Merge `src` over `dst`, recursively for a table over a table; anything else replaces.
local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" and #v == 0 then
            merge(dst[k], v)
        else
            dst[k] = copy(v)
        end
    end
end

local NO_CHIPS = {}

--- The spell chips container `c` shows: its stored `elements.spells.list` once the player has chosen
--- one (a non-empty list), else the LOGGED-IN character's class seeds for this client. Resolved at
--- render time, never stored on create: the Default profile is shared by every character, so a list
--- seeded for the creating character's class would show an alt of another class spells it does not
--- have (savedvariables-§5: a stored choice survives; nothing is re-seeded over it). The answer is
--- read-only (the seed table itself), and the renderer resolves it once per apply, not per tick.
--- @return table  an array of spell IDs
function CM.SpellChips(c)
    local sp = type(c) == "table" and type(c.elements) == "table" and c.elements.spells
    local list = type(sp) == "table" and sp.list
    if type(list) == "table" and #list > 0 then return list end
    local byClient = NS.SpellSeeds and NS.SpellSeeds[NS.Compat.ClientKey()]
    local seeds = byClient and byClient[NS.Compat.PlayerClass() or ""]
    return seeds and seeds.chips or NO_CHIPS
end

--- Mint the next id and store `c` under it, after `afterId` in the order when given, else last.
local function insert(p, c, afterId)
    local id = p.nextContainerId or 1
    p.nextContainerId = id + 1
    p.containers[id] = c
    local pos = #p.containerOrder + 1
    for i, other in ipairs(p.containerOrder) do
        if other == afterId then pos = i + 1 end
    end
    table.insert(p.containerOrder, pos, id)
    return id
end

--- The new-container offset of id `id`: down from the center, eight rows of 30 before it wraps.
local function staggerY(id)
    return 0 - (((tonumber(id) or 1) - 1) % 8) * 30
end

--- A new container on `unit` from the template: the default band set (no spell list: the chips
--- resolve to the logged-in class's seeds, CM.SpellChips), then `opts` merged over it, and a unique name (opts.name, else the unit's). opts.unit is ignored:
--- the positional `unit` is the one checked against the watched units, so it is the one stored. A new
--- screen container is staggered down from the center by its id, so two new ones never stack exactly.
--- Answers its id, or nil for a unit RangeMaster does not watch or before the db exists.
function CM.Create(unit, opts)
    local p = profile()
    unit = unit or "target"
    if not (p and p.containers and UNIT_NAME[unit]) then return nil end
    local c = copy(NS.CONTAINER_TEMPLATE)
    c.unit, c.bandSet = unit, NS.BandSets.DefaultId()
    c.anchor.y = staggerY(p.nextContainerId or 1)
    if type(opts) == "table" then merge(c, opts) end
    c.unit = unit
    c.name = CM.UniqueName(type(opts) == "table" and opts.name or UNIT_NAME[unit])
    local id = insert(p, c)
    NS.Debug("Containers", "created %s '%s' (%s)", id, c.name, unit)
    CM.RequestApply()
    return id
end

--- Store where container `id` sits: `point` of the frame on `relPoint` of its anchor, offset `x`, `y`
--- (whole numbers). Refuses an unknown id and non-numeric offsets.
function CM.SetPosition(id, point, relPoint, x, y)
    local c = CM.Get(id)
    if not c or type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return false end
    local a = c.anchor
    a.point, a.relPoint, a.x, a.y = point, relPoint or point, x, y
    NS.Debug("Containers", "moved %s to %s %s %d %d", id, point, a.relPoint, x, y)
    CM.RequestApply()
    return true
end

--- The fields whose template value is nil, and what each may hold: a band-set id (nil = the default
--- set for `bandSet`, "use bandSet for every reaction" for `bandSetFriendly`).
local NILABLE = { bandSet = true, bandSetFriendly = true }
--- Fields with a writer of their own, never written here: the name is Rename's (unique, trimmed).
local OWN_WRITER = { name = true }

--- The template's value at dotted `field`, or nil.
local function templateValue(field)
    local node = NS.CONTAINER_TEMPLATE
    for seg in field:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[seg]
    end
    return node
end

--- Whether `v` is an arrangement of the template's elements: an array naming each exactly once.
function CM.IsElementOrder(v)
    local names = NS.CONTAINER_TEMPLATE.elements.order
    if type(v) ~= "table" or #v ~= #names then return false end
    local want, seen, n = {}, {}, 0
    for _, name in ipairs(names) do want[name] = true end
    for _ in pairs(v) do n = n + 1 end
    if n ~= #v then return false end
    for _, name in ipairs(v) do
        if not want[name] or seen[name] then return false end
        seen[name] = true
    end
    return true
end

--- Whether `value` may be stored at `field`: a band-set reference names a stored set (or is nil), the
--- unit is one RangeMaster watches, the element order is an arrangement of the four elements, and
--- anything else has the template leaf's type.
local function acceptable(field, value)
    if NILABLE[field] then return value == nil or NS.BandSets.Get(value) ~= nil end
    if field == "unit" then return UNIT_NAME[value] ~= nil end
    if field == "elements.order" then return CM.IsElementOrder(value) end
    local leaf = templateValue(field)
    return leaf ~= nil and type(leaf) == type(value)
end

--- Write `value` (a copy) at dotted `field` of `c`, making the tables on the way.
local function writeField(c, field, value)
    local node, parts = c, {}
    for seg in field:gmatch("[^%.]+") do parts[#parts + 1] = seg end
    for i = 1, #parts - 1 do
        if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
        node = node[parts[i]]
    end
    node[parts[#parts]] = copy(value)
end

--- Store one setting of container `id`: `field` is a dotted path inside the container
--- ("anchor.mode", "elements.number.size"). A nil `bandSet` stores the default set. Refuses an
--- unknown id, a field the template does not have, a value of the wrong type, and the name (Rename).
function CM.SetField(id, field, value)
    local c = CM.Get(id)
    if not c or type(field) ~= "string" or OWN_WRITER[field] then return false end
    if field == "bandSet" and value == nil then value = NS.BandSets.DefaultId() end
    if not acceptable(field, value) then return false end
    -- No line of its own: the schema seam's [Set] line already names the write.
    writeField(c, field, value)
    CM.RequestApply()
    return true
end

--- Put container `id` back at the point a new container takes (the center, staggered by its id).
function CM.ResetPosition(id)
    return CM.SetPosition(id, "CENTER", "CENTER", 0, staggerY(id))
end

--- Delete container `id`. Refuses an unknown id.
function CM.Delete(id)
    local p = profile()
    if not (p and p.containers and p.containers[id]) then return false end
    p.containers[id] = nil
    for i = #p.containerOrder, 1, -1 do
        if p.containerOrder[i] == id then table.remove(p.containerOrder, i) end
    end
    NS.Debug("Containers", "deleted %s", id)
    CM.RequestApply()
    return true
end

--- A copy of container `id` with every setting, right after it in the order, named "<name> copy"
--- (made unique). A screen copy is offset so it does not sit exactly on its source. Answers the new
--- id, or nil.
function CM.Duplicate(id)
    local p, src = profile(), CM.Get(id)
    if not src then return nil end
    local c = copy(src)
    c.name = CM.UniqueName(L["%s copy"]:format(src.name))
    if c.anchor.mode == "screen" then
        c.anchor.x = (tonumber(c.anchor.x) or 0) + 20
        c.anchor.y = (tonumber(c.anchor.y) or 0) - 20
    end
    local newId = insert(p, c, id)
    NS.Debug("Containers", "duplicated %s -> %s", id, newId)
    CM.RequestApply()
    return newId
end

--- Rename container `id` (trimmed, made unique against the others). Refuses a blank name or an
--- unknown id.
function CM.Rename(id, name)
    local c = CM.Get(id)
    name = trim(name)
    if not c or name == "" then return false end
    c.name = CM.UniqueName(name, id)
    CM.RequestApply()
    return true
end

--- Copy `sections` (default CM.COPY_SECTIONS) from `fromId` onto `toId`, deep. All or nothing:
--- refuses an unknown id, a container copying itself, and any section that is not copyable.
function CM.CopySettings(fromId, toId, sections)
    local src, dst = CM.Get(fromId), CM.Get(toId)
    if not (src and dst) or fromId == toId then return false end
    sections = sections or CM.COPY_SECTIONS
    for _, key in ipairs(sections) do
        if not COPYABLE[key] then return false end
    end
    for _, key in ipairs(sections) do dst[key] = copy(src[key]) end
    NS.Debug("Containers", "copied %d section(s) %s -> %s", #sections, fromId, toId)
    CM.RequestApply()
    return true
end

local SNAPSHOT_FIELDS = { "containers", "containerOrder", "nextContainerId" }

--- A deep copy of the container registry and the band sets, in the shape RestoreSnapshot takes.
--- Nil when there is no profile.
function CM.Snapshot()
    local p = profile()
    if type(p) ~= "table" then return nil end
    local snap = { bandSets = NS.BandSets.Snapshot() }
    for _, field in ipairs(SNAPSHOT_FIELDS) do snap[field] = copy(p[field]) end
    return snap
end

--- Put snapshot `snap` back: the containers and their order replaced by copies (ids kept, so the
--- snapshot stays reusable), then the band sets through their own writer. The id counter is never
--- rewound: it keeps the higher of its own and the snapshot's, so an id minted after the snapshot is
--- never handed to a different container (the renderer's pool and a selection key by id).
function CM.RestoreSnapshot(snap)
    local p = profile()
    if type(snap) ~= "table" or type(p) ~= "table" or type(snap.containers) ~= "table" then return false end
    local counter = math.max(tonumber(p.nextContainerId) or 1, tonumber(snap.nextContainerId) or 1)
    for _, field in ipairs(SNAPSHOT_FIELDS) do p[field] = copy(snap[field]) end
    p.nextContainerId = counter
    if type(p.containerOrder) ~= "table" then p.containerOrder = {} end
    if snap.bandSets then NS.BandSets.RestoreSnapshot(snap.bandSets) end
    NS.Debug("Containers", "restored a snapshot: %d container(s)", #p.containerOrder)
    CM.RequestApply()
    return true
end

--- Record that the first-run preset picker was shown (or a preset applied) on the active profile:
--- the registry's sentinel, so it is written here and nowhere else (architecture-§5).
function CM.MarkSeeded()
    local p = profile()
    if type(p) == "table" and p.seeded ~= true then
        p.seeded = true
        NS.Debug("Presets", "first-run picker marked seen")
    end
end

--- Delete every container (a preset replacing the profile's set). Answers how many went.
function CM.Clear()
    local ids = CM.List()
    for _, id in ipairs(ids) do CM.Delete(id) end
    return #ids
end
