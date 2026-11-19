local _, NS = ...
-- modules/Presets.lua — the container presets (design spec 5.2, "Container presets"; the mockup's
-- presets board; the five-preset plan of 2026-11-19, M4): Simple, Intermediate (Range Text),
-- Intermediate (Range Numbers), Advanced and Expert, shown on first run and on General › Presets
-- (plan Task 8).
--
--   NS.Presets.Apply(key) -> snapshotBefore   key ∈ NS.Presets.ORDER; nil (and nothing done) otherwise
--   NS.Presets.Undo() -> boolean              one level: the snapshot the last Apply took
--   NS.Presets.CanUndo() -> boolean
--   NS.Presets.ForgetUndo()                   drop the slot (a profile switch, copy or reset)
--   NS.Presets.Describe(key) -> { name, count, items }   what the preset card shows
--   NS.Presets.PickerDue() -> boolean        the first-run picker has not been shown on this profile
--   NS.Presets.MarkPickerSeen()              it has (profile.seeded, written by NS.CM.MarkSeeded)
--   NS.Presets.BeginPreview(key) -> boolean  the first-run picker's pick: the preset put on screen
--   NS.Presets.EndPreview(keep) -> boolean   kept (Undo then restores what was there) or restored
--   NS.Presets.DropPreview()                 forget a preview the profile no longer holds
--   NS.Presets.IsPreviewing(), Previewed()   whether one is up, and its key
--   NS.Presets.OwnContainerCount()           the player's own container count, under a preview too
--
-- APPLYING REPLACES THE PROFILE'S CONTAINERS, and only through the registry's writer (NS.CM): every
-- container goes, the preset's are created, and the coalesced apply announces once on the next frame.
-- The confirm before it is the caller's (the Presets tab, `/rm preset`, plan Task 8).
--
-- THE BAND SETS ARE THE PLAYER'S, picked for their class on first run: every preset container uses
-- the default set. Expert alone touches the band-set registry, through its writers and only to add:
-- its friendly override is the "Healer" set (the one named so, else a new one from the healer
-- preset), and its out-of-range warning puts OOR_SOUND on the last band of the target's set when
-- that band has no sound yet (NS.BandSets.SetBandSound). Undo restores both registries
-- (NS.CM.Snapshot).
--
-- THE UNDO SLOT BELONGS TO THE PROFILE IT WAS TAKEN ON. A switch, copy or reset replaces the profile
-- whole, so core/RangeMaster.lua's adoptProfile calls ForgetUndo: an Undo there would otherwise put
-- the old profile's containers and band sets over the new one's.
--
-- EVERY UNIT HAS ONE HOME ON SCREEN, the same in every preset (HOME, below): a grid of two columns
-- below the screen's center, wide enough that two drag strips side by side never overlap and tall
-- enough for a preview nameplate over a nameplate container. A screen container sits at its home; a
-- nameplate container waits there while the displays are unlocked.
--
-- What each preset holds (the owner's rulings of 2026-11-19). Every one puts Target, Focus, Pet and
-- Mouseover FREE ON SCREEN at their homes, on the template's frame (background and band-colored
-- border on, the border at its default opacity) with the template's dot (shape and matte style are
-- the template's, defaults/Profile.lua, so neither is written here); only the elements shown differ:
--   Simple                         the dot.
--   Intermediate (Range Text)      the band's text label.
--   Intermediate (Range Numbers)   the range number.
--   Advanced                       dot + number + text.
--   Expert                         dot + number + text + spell chips; the Healer set for friendly
--                                  target, focus and mouseover, the OOR sound on Target; plus Target
--                                  on its own nameplate (diamond + number) and every hostile
--                                  nameplate (dot + the short `max` number), both in combat only.

NS.Presets = NS.Presets or {}
local Presets = NS.Presets

local L = NS.L

Presets.ORDER = { "simple", "text", "numbers", "advanced", "expert" }

--- The LSM sound key Expert puts on the out-of-range band. Registered with LibSharedMedia by the
--- band sounds (modules/Sounds.lua's BUILTIN, the raid warning chime), so it plays without LSM too.
Presets.OOR_SOUND = "Ka0s Range Master: Out of range"

local lastSnapshot   -- the one Undo level
local preview        -- the picker's preview while one is up: { key, origin = the player's snapshot }

-- ---------------------------------------------------------------------------
-- The presets, as (unit, opts) lists for NS.CM.Create
-- ---------------------------------------------------------------------------

-- The homes (EVERY UNIT HAS ONE HOME ON SCREEN): columns COL_X either side of the center line, rows
-- from ROW_Y down by ROW_STEP. Target and focus share the first row, pet and mouseover the second,
-- the two nameplate containers the third.
local COL_X, ROW_Y, ROW_STEP = 135, -100, 90
local HOME = {
    target = { -1, 0 }, focus = { 1, 0 }, pet = { -1, 1 }, mouseover = { 1, 1 },
    targetPlate = { -1, 2 }, nameplates = { 1, 2 },
}
Presets.HOME = HOME

--- `anchor` (a preset's anchor table) given the screen point of home `slot`; answers it.
local function home(anchor, slot)
    local h = HOME[slot]
    anchor.point, anchor.relPoint = "CENTER", "CENTER"
    anchor.x, anchor.y = h[1] * COL_X, ROW_Y - h[2] * ROW_STEP
    return anchor
end
Presets.__home = function(slot) return home({}, slot) end

--- One of the four unit containers, free on screen at its home, showing the elements `show` names
--- (`dot`, `number`, `text`, `spells`) and no other.
local function onScreen(unit, show)
    return { unit = unit, opts = {
        anchor = home({ mode = "screen" }, unit),
        elements = {
            indicator = { enabled = show.dot == true }, number = { enabled = show.number == true },
            text = { enabled = show.text == true }, spells = { enabled = show.spells == true },
        },
    } }
end

--- The four units on screen, each showing `show`.
local function four(show)
    return { onScreen("target", show), onScreen("focus", show), onScreen("pet", show),
        onScreen("mouseover", show) }
end

--- The Healer band set's id: the stored set named so, else a new one from the healer preset.
local function healerSet()
    for _, id in ipairs(NS.BandSets.List()) do
        if NS.BandSets.Get(id).name == L["Healer"] then return id end
    end
    return NS.BandSets.Create(nil, "healer")
end

--- One nameplate container: indicator `shape` + number in `format`, shown in combat only; `extra`'s
--- keys (a name, a section) replace the opts' own.
local function plate(unit, slot, shape, format, extra)
    local opts = {
        anchor = home({ mode = "nameplate" }, slot),
        elements = { indicator = { enabled = true, shape = shape }, number = { format = format } },
        visibility = { combat = "in", hideNoUnit = true },
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return { unit = unit, opts = opts }
end

local function expert()
    local list = four({ dot = true, number = true, text = true, spells = true })
    local healer = healerSet()
    for i = 1, #list do
        if list[i].unit ~= "pet" then list[i].opts.bandSetFriendly = healer end   -- a pet is always friendly
    end
    list[1].opts.sounds = { enabled = true }
    list[#list + 1] = plate("target", "targetPlate", "diamond", "range", { name = L["Target plate"] })
    list[#list + 1] = plate("nameplates", "nameplates", "dot", "max", {
        visibility = { combat = "in", reaction = "hostile", hideNoUnit = true },
        nameplate = { includeFriendly = false },
    })
    return list
end

local BUILD = {
    simple   = function() return four({ dot = true }) end,
    text     = function() return four({ text = true }) end,
    numbers  = function() return four({ number = true }) end,
    advanced = function() return four({ dot = true, number = true, text = true }) end,
    expert   = expert,
}

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

--- Replace the profile's containers with preset `key`'s (a known key).
local function build(key)
    NS.CM.Clear()
    for _, entry in ipairs(BUILD[key]()) do
        local id = NS.CM.Create(entry.unit, entry.opts)
        if entry.opts.sounds and entry.opts.sounds.enabled then addOorSound(id) end
    end
end

--- Apply preset `key`: snapshot, clear, create. Answers the snapshot taken before, or nil for an
--- unknown key (nothing changed, the Undo slot kept). A preview up is ended with a restore first,
--- so the snapshot is the player's own set.
function Presets.Apply(key)
    if not BUILD[key] or not NS.CM.Get then return nil end
    if preview then Presets.EndPreview(false) end
    local before = NS.CM.Snapshot()
    if not before then return nil end
    build(key)
    lastSnapshot = before
    NS.Debug("Presets", "applied %s: %d container(s)", key, #NS.CM.List())
    return before
end

-- ---------------------------------------------------------------------------
-- Previewing (the first-run picker, settings/Presets.lua)
-- ---------------------------------------------------------------------------
--
-- A PICK IN THE PICKER PUTS THE PRESET ON THE REAL SCREEN through the same writer an Apply uses; the
-- player's own set is snapshotted ONCE, at the first pick, so a second pick swaps one preview for
-- another and the snapshot is still theirs. Keeping it makes that snapshot the Undo slot (Undo puts
-- back what was there before the picker); ending it without keeping restores it. The preview lives in
-- the profile while it is up, so the picker ends it before anything else can read or save that
-- profile: AceDB's OnProfileShutdown (a switch) and OnDatabaseShutdown (a logout or a /reload, before
-- SavedVariables are written) restore it into the profile it was taken on, and a reset or a copy,
-- which replace the profile whole, drop it (DropPreview). Combat start restores it too.

--- Preview preset `key`: the player's set snapshotted at the first pick, then the preset built.
--- A later pick first puts the player's set back, so what an earlier pick added to the band sets
--- (Expert's Healer set and out-of-range sound) does not outlive it into the preset kept.
--- Answers false for an unknown key or no profile (nothing changed).
function Presets.BeginPreview(key)
    if not BUILD[key] or not NS.CM.Get then return false end
    local origin = preview and preview.origin or NS.CM.Snapshot()
    if not origin then return false end
    if preview then NS.CM.RestoreSnapshot(origin) end
    build(key)
    preview = { key = key, origin = origin }
    NS.Debug("Presets", "previewing %s: %d container(s)", key, #NS.CM.List())
    return true
end

--- End the preview: `keep` true leaves the preset in place (the player's set becomes the Undo slot),
--- false puts the player's set back. Answers false when none was up.
function Presets.EndPreview(keep)
    if not preview then return false end
    local p = preview
    preview = nil
    if keep then
        lastSnapshot = p.origin
        NS.Debug("Presets", "kept the %s preview", p.key)
    else
        NS.CM.RestoreSnapshot(p.origin)
        NS.Debug("Presets", "preview of %s ended: restored", p.key)
    end
    return true
end

--- Forget the preview without restoring: the profile it was taken on was replaced whole.
function Presets.DropPreview()
    if preview then NS.Debug("Presets", "preview dropped: the profile was replaced") end
    preview = nil
end

function Presets.IsPreviewing() return preview ~= nil end

--- The key of the preset previewed now, or nil.
function Presets.Previewed() return preview and preview.key or nil end

--- How many containers are the player's own: the snapshot's under a preview, the registry's else.
function Presets.OwnContainerCount()
    if preview then return #(preview.origin.containerOrder or {}) end
    return #NS.CM.List()
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
-- core/Database.lua's load pass creates `seeded` as false on a profile that has none; its one runtime
-- writer is the container registry's (NS.CM.MarkSeeded), which this reaches. settings/Presets.lua shows the picker while it is due and marks it seen as it shows,
-- so a /reload, a dismissal by Escape or a crash never offers it twice on one profile.

--- Whether the first-run preset picker is still owed on the active profile.
function Presets.PickerDue()
    local p = NS.db and NS.db.profile
    return type(p) == "table" and p.seeded == false
end

--- Record that the picker was shown (or a preset applied) on the active profile.
function Presets.MarkPickerSeen()
    NS.CM.MarkSeeded()
end

-- Suite seam (tests/test_presets.lua).
function Presets.__reset() lastSnapshot, preview = nil, nil end

-- ---------------------------------------------------------------------------
-- Describing (the preset cards)
-- ---------------------------------------------------------------------------

local ON_SCREEN = L["Target, Focus, Pet, Mouseover: free on screen"]
local ONE_SET = L["One band set (class default)"]
local NO_SOUNDS = L["No sounds, always visible when the unit exists"]

local DESCRIBE = {
    simple = { name = L["Simple"], count = 4, items = {
        ON_SCREEN, L["A dot colored by band"], ONE_SET, NO_SOUNDS,
    } },
    text = { name = L["Intermediate (Range Text)"], count = 4, items = {
        ON_SCREEN, L["The band's label as text"], ONE_SET, NO_SOUNDS,
    } },
    numbers = { name = L["Intermediate (Range Numbers)"], count = 4, items = {
        ON_SCREEN, L["The range number"], ONE_SET, NO_SOUNDS,
    } },
    advanced = { name = L["Advanced"], count = 4, items = {
        ON_SCREEN, L["Dot + range number + text label"], ONE_SET, NO_SOUNDS,
    } },
    expert = { name = L["Expert"], count = 6, items = {
        L["Everything in Advanced, with spell-range chips (class spells)"],
        L["Healer band set for friendly target, focus and mouseover"],
        L["Target on its own nameplate + dot on all hostile plates"],
        L["Band-change sound on target (out-of-range warning)"],
        L["Visibility rules: nameplates in combat only, hostile only"],
    } },
}

--- What preset `key`'s card shows, as a new table: { name, count, items }. Nil for an unknown key.
function Presets.Describe(key)
    local d = DESCRIBE[key]
    if not d then return nil end
    return NS.Database.DeepCopy(d)
end
