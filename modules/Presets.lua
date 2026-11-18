local _, NS = ...
-- modules/Presets.lua — the container presets (design spec 5.2, "Container presets"; the mockup's
-- presets board): Simple, Intermediate and Advanced, shown on first run and on General › Presets
-- (plan Task 8).
--
--   NS.Presets.Apply(key) -> snapshotBefore   key ∈ NS.Presets.ORDER; nil (and nothing done) otherwise
--   NS.Presets.Undo() -> boolean              one level: the snapshot the last Apply took
--   NS.Presets.CanUndo() -> boolean
--   NS.Presets.ForgetUndo()                   drop the slot (a profile switch, copy or reset)
--   NS.Presets.Describe(key) -> { name, count, items }   what the preset card shows
--   NS.Presets.PickerDue() -> boolean        the first-run picker has not been shown on this profile
--   NS.Presets.MarkPickerSeen()              it has (profile.seeded, this file its one runtime writer)
--
-- APPLYING REPLACES THE PROFILE'S CONTAINERS, and only through the registry's writer (NS.CM): every
-- container goes, the preset's are created, and the coalesced apply announces once on the next frame.
-- The confirm before it is the caller's (the Presets tab, `/rm preset`, plan Task 8).
--
-- THE BAND SETS ARE THE PLAYER'S, picked for their class on first run: every preset container uses
-- the default set. Two presets touch the band-set registry, each through its writer and only to add:
-- Intermediate's friendly override is the "Healer" set (the one named so, else a new one from the
-- healer preset), and Advanced's out-of-range warning puts OOR_SOUND on the last band of the
-- target's set when that band has no sound yet (NS.BandSets.SetBandSound). Undo restores both
-- registries (NS.CM.Snapshot).
--
-- THE UNDO SLOT BELONGS TO THE PROFILE IT WAS TAKEN ON. A switch, copy or reset replaces the profile
-- whole, so core/RangeMaster.lua's adoptProfile calls ForgetUndo: an Undo there would otherwise put
-- the old profile's containers and band sets over the new one's.
--
-- What each preset holds (the spec's text, where the mockup's Simple card shows three containers,
-- the spec and the plan name four):
--   Simple        Target, Focus, Pet, Mouseover, free on screen; number + band-colored border.
--   Intermediate  Target / Focus / Pet on their Blizzard unit frames, Mouseover on the cursor;
--                 number + text + dot; Healer set for friendly target, focus and mouseover;
--                 hidden while there is no unit.
--   Advanced      Intermediate, with spell chips on Focus and the OOR sound on Target; plus Target on
--                 its own nameplate (diamond + number) and every hostile nameplate (dot + the short
--                 `max` number), both shown in combat only.

NS.Presets = NS.Presets or {}
local Presets = NS.Presets

local L = NS.L

Presets.ORDER = { "simple", "intermediate", "advanced" }

--- The LSM sound key Advanced puts on the out-of-range band. Registered with LibSharedMedia by the
--- band sounds (modules/Sounds.lua's BUILTIN, the raid warning chime), so it plays without LSM too.
Presets.OOR_SOUND = "Ka0s Range Master: Out of range"

local lastSnapshot   -- the one Undo level

-- ---------------------------------------------------------------------------
-- The presets, as (unit, opts) lists for NS.CM.Create
-- ---------------------------------------------------------------------------

--- Simple: the four units, free on screen in a two-by-two block below the center.
local function simple()
    local function at(unit, x, y)
        return { unit = unit, opts = { anchor = { mode = "screen", x = x, y = y } } }
    end
    return { at("target", -70, -140), at("focus", 70, -140), at("pet", -70, -180), at("mouseover", 70, -180) }
end

--- The Healer band set's id: the stored set named so, else a new one from the healer preset.
local function healerSet()
    for _, id in ipairs(NS.BandSets.List()) do
        if NS.BandSets.Get(id).name == L["Healer"] then return id end
    end
    return NS.BandSets.Create(nil, "healer")
end

--- One Intermediate container: number + text + dot, hidden with no unit, `anchor` its placement.
local function shown(unit, anchor, friendly)
    return { unit = unit, opts = {
        anchor = anchor, bandSetFriendly = friendly,
        elements = { text = { enabled = true }, indicator = { enabled = true, shape = "dot" } },
        visibility = { hideNoUnit = true },
    } }
end

local function onFrame() return { mode = "frame", frame = { provider = "blizzard", name = "" } } end

local function intermediate()
    local healer = healerSet()
    return {
        shown("target", onFrame(), healer), shown("focus", onFrame(), healer), shown("pet", onFrame()),
        shown("mouseover", { mode = "cursor" }, healer),
    }
end

--- One nameplate container: indicator `shape` + number in `format`, shown in combat only; `extra`'s
--- keys (a name, a section) replace the opts' own.
local function plate(unit, shape, format, extra)
    local opts = {
        anchor = { mode = "nameplate" },
        elements = { indicator = { enabled = true, shape = shape }, number = { format = format } },
        visibility = { combat = "in", hideNoUnit = true },
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return { unit = unit, opts = opts }
end

local function advanced()
    local list = intermediate()
    list[1].opts.sounds = { enabled = true }
    list[2].opts.elements.spells = { enabled = true }
    list[#list + 1] = plate("target", "diamond", "range", { name = L["Target plate"] })
    list[#list + 1] = plate("nameplates", "dot", "max", {
        visibility = { combat = "in", reaction = "hostile", hideNoUnit = true },
        nameplate = { includeFriendly = false },
    })
    return list
end

local BUILD = { simple = simple, intermediate = intermediate, advanced = advanced }

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------

--- Put OOR_SOUND on the last (open-ended) band of container `id`'s set, unless it has a sound.
local function addOorSound(id)
    local c = NS.CM.Get(id)
    local set = c and NS.BandSets.Get(c.bandSet)
    local last = set and set.bands[#set.bands]
    if not last or last.sound ~= nil then return end
    NS.BandSets.SetBandSound(c.bandSet, #set.bands, Presets.OOR_SOUND)
end

--- Apply preset `key`: snapshot, clear, create. Answers the snapshot taken before, or nil for an
--- unknown key (nothing changed, the Undo slot kept).
function Presets.Apply(key)
    local build = BUILD[key]
    if not build or not NS.CM.Get then return nil end
    local before = NS.CM.Snapshot()
    if not before then return nil end
    NS.CM.Clear()
    for _, entry in ipairs(build()) do
        local id = NS.CM.Create(entry.unit, entry.opts)
        if entry.opts.sounds and entry.opts.sounds.enabled then addOorSound(id) end
    end
    lastSnapshot = before
    NS.Debug("Presets", "applied %s: %d container(s)", key, #NS.CM.List())
    return before
end

--- Whether an Undo is available.
function Presets.CanUndo()
    return lastSnapshot ~= nil
end

--- Put back what the last Apply replaced. One level: answers false when there is nothing to undo.
function Presets.Undo()
    if not lastSnapshot then return false end
    local snap = lastSnapshot
    lastSnapshot = nil
    NS.Debug("Presets", "undo")
    return NS.CM.RestoreSnapshot(snap)
end

--- Drop the Undo slot: the profile it was taken on is no longer the one in use.
function Presets.ForgetUndo()
    if lastSnapshot then NS.Debug("Presets", "undo dropped: the profile changed") end
    lastSnapshot = nil
end

-- ---------------------------------------------------------------------------
-- The first-run picker's sentinel (profile.seeded)
-- ---------------------------------------------------------------------------
--
-- core/Database.lua's load pass creates `seeded` as false on a profile that has none; this is its one
-- runtime writer. settings/Presets.lua shows the picker while it is due and marks it seen as it shows,
-- so a /reload, a dismissal by Escape or a crash never offers it twice on one profile.

--- Whether the first-run preset picker is still owed on the active profile.
function Presets.PickerDue()
    local p = NS.db and NS.db.profile
    return type(p) == "table" and p.seeded == false
end

--- Record that the picker was shown (or a preset applied) on the active profile.
function Presets.MarkPickerSeen()
    local p = NS.db and NS.db.profile
    if type(p) == "table" and p.seeded ~= true then
        p.seeded = true
        NS.Debug("Presets", "first-run picker marked seen")
    end
end

-- Suite seam (tests/test_presets.lua).
function Presets.__reset() lastSnapshot = nil end

-- ---------------------------------------------------------------------------
-- Describing (the preset cards)
-- ---------------------------------------------------------------------------

local DESCRIBE = {
    simple = { name = L["Simple"], count = 4, items = {
        L["Target, Focus, Pet, Mouseover: free on screen"],
        L["Number + frame colored by band"],
        L["One band set (class default)"],
        L["No sounds, always visible when the unit exists"],
    } },
    intermediate = { name = L["Intermediate"], count = 4, items = {
        L["Target / Focus / Pet attached to their unit frames"],
        L["Mouseover follows the cursor"],
        L["Number + text label + dot"],
        L["Hostile vs friendly band sets"],
        L["Hidden while there is no unit"],
    } },
    advanced = { name = L["Advanced"], count = 6, items = {
        L["Everything in Intermediate"],
        L["Target on its own nameplate + dot on all hostile plates"],
        L["Focus with spell-range chips (class spells)"],
        L["Band-change sound (out-of-range warning)"],
        L["Visibility rules: nameplates in combat only, hostile only"],
    } },
}

--- What preset `key`'s card shows, as a new table: { name, count, items }. Nil for an unknown key.
function Presets.Describe(key)
    local d = DESCRIBE[key]
    if not d then return nil end
    return NS.Database.DeepCopy(d)
end
