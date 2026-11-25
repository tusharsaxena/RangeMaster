local _, NS = ...
-- modules/Sounds.lua — the band sounds (design spec 5.5): a container plays the sound of the band it
-- has settled in, debounced.
--
--   NS.Sounds.OnBand(inst, bandIndex, now) -> played   the renderer's report of the band an instance
--                                       draws, on every render and every steady read of its unit
--   NS.Sounds.Reset(inst)               a different unit sits behind the instance: forget its bands
--                                       (the next one settles silently), keep the gap
--   NS.Sounds.Wants(inst) -> boolean    a container with sounds on, and never a `nameplates` one
--   NS.Sounds.SETTLE, GAP, BUILTIN      0.2 s, 1 s, and the sound keys this addon ships
--
-- THE STATE LIVES ON THE RENDER INSTANCE, `inst.sound = { band, since, settled, lastPlay, first }`
-- (one instance per container; a `nameplates` container's per-plate instances never get one). A band
-- reported for the first time starts its settle (`band`, `since`). Once the same band is reported
-- SETTLE or more after `since` it has settled: if it is not the band that settled last (`settled`), its
-- sound plays, unless it is the first band since the unit changed (`first`, set by Reset and by the
-- unit going away) or the last sound played less than GAP ago (`lastPlay`, per container: Reset keeps
-- it, so a retarget, a faction change or a preview starting or ending never opens the gap). A band left
-- inside its settle never plays, and a flicker out of a band and back is quiet, because coming back
-- settles the band that had settled already. An unknown range settles nothing and resets nothing.
--
-- WHO REPORTS. modules/Container.lua, from a shown instance only: after a render resolves its band,
-- and on each steady read of its unit (NS.Ticker.OnSteady), which is what lets a band that holds
-- still be heard settling without a timer of its own. A hidden container plays nothing.
--
-- THE SOUND is the band's LibSharedMedia key (`bands[i].sound`, design spec 5.2), resolved at play
-- time through LSM, else through BUILTIN, and played with PlaySoundFile on the container's channel
-- (`sounds.channel`), under pcall. A key neither knows plays nothing. BUILTIN is registered with LSM
-- at load, so the band-sound picker lists it beside every other addon's sounds.

NS.Sounds = NS.Sounds or {}
local Sounds = NS.Sounds

Sounds.SETTLE = 0.2
Sounds.GAP = 1

-- The keys this addon ships, each a stock game sound's file id (no audio file is bundled). The
-- out-of-range warning is the raid warning chime (sound/interface/raidwarning.ogg), present on both
-- clients.
Sounds.BUILTIN = {
    [NS.Presets.OOR_SOUND] = 567397,
}

local CHANNELS = { Master = true, SFX = true, Music = true, Ambience = true, Dialog = true }

function Sounds.Wants(inst)
    local c = inst and inst.container
    local s = c and c.sounds
    return s ~= nil and s.enabled == true and not NS.CM.IsPlates(c.unit) and inst.plateToken == nil
end

function Sounds.Reset(inst)
    local s = inst and inst.sound
    if not s then return end
    s.band, s.since, s.done, s.settled, s.first = nil, nil, nil, nil, true
end

local function resolve(key)
    local LSM = NS.GetLSM()
    local file = LSM and LSM:Fetch("sound", key, true)
    return file or Sounds.BUILTIN[key]
end

--- The sound key of band `band` of the set the instance draws, or nil.
local function keyFor(inst, band)
    local B = NS.BandSets
    local set = B.Get(inst.setId or B.ForUnit(inst.container, inst.unit, inst.id))
    local row = set and set.bands and set.bands[band]
    local key = row and row.sound
    if type(key) ~= "string" or key == "" then return nil end
    return key
end

local function play(inst, band)
    local key = keyFor(inst, band)
    local file = key and resolve(key)
    if not file or not PlaySoundFile then return false end
    local channel = inst.container.sounds.channel
    if not CHANNELS[channel] then channel = "Master" end
    local ok, willPlay = pcall(PlaySoundFile, file, channel)
    return ok and willPlay ~= false
end

--- The band just settled: play it, or say why not.
local function settle(inst, s, band, now)
    if band == "none" then
        s.first, s.settled = true, nil
        return false
    end
    if type(band) ~= "number" or band == s.settled then return false end
    s.settled = band
    if s.first then
        s.first = false
        return false
    end
    if s.lastPlay and now - s.lastPlay < Sounds.GAP - 1e-9 then return false end
    if not play(inst, band) then return false end
    s.lastPlay = now
    return true
end

--- Report the band `inst` draws at time `now` (GetTime()). Answers whether a sound played.
function Sounds.OnBand(inst, band, now)
    if not Sounds.Wants(inst) or type(now) ~= "number" then return false end
    local s = inst.sound
    if not s then
        s = { first = true }
        inst.sound = s
    end
    if band ~= s.band then
        s.band, s.since, s.done = band, now, false
        return false
    end
    if s.done or now - s.since < Sounds.SETTLE - 1e-9 then return false end
    s.done = true
    return settle(inst, s, band, now)
end

-- Registered with LibSharedMedia at load (the vendored LSM has already run, core/MediaSetup.lua).
do
    local LSM = NS.GetLSM()
    if LSM and LSM.Register then
        for key, file in pairs(Sounds.BUILTIN) do LSM:Register("sound", key, file) end
    end
end
