-- tests/test_sounds.lua — the band sounds (modules/Sounds.lua, NS.Sounds; design spec 5.5): a band's
-- sound plays once the band has held for the settle (0.2 s), never within the gap (1 s) of the last
-- one, never for the first band after the unit changed, and never for a `nameplates` container. The
-- state lives on the render instance. The v0.1.0 plan, Task 7.
--
-- PlaySoundFile is spied, so every case counts what would have reached the client. The clock is the
-- kit's settable GetTime (M.__now).

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile("tests/anchors_env.lua")
local installPaint = dofile("tests/_kit/mock_paint.lua")

--- H.with under the kit's paint recorder (font strings that keep their text, frames their opacity and
--- scale), with the combat edge put back however the case ends.
local function withEnv(body)
  local restore = installPaint(M)
  local ok, err = pcall(H.with, body)
  restore()
  M.InCombatLockdown = function() return false end
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  if not ok then error(err, 0) end
end

local S, B = NS.Sounds, NS.BandSets

--- Run `body(played, inst, setId)` on a fresh profile with a sounding target container whose every
--- band carries the built-in out-of-range sound; `played` collects each PlaySoundFile call.
local function withSounds(body, opts)
  withEnv(function()
    local played = {}
    local savedPlay, savedNow = M.PlaySoundFile, M.__now
    M.PlaySoundFile = function(file, channel)
      played[#played + 1] = { file = file, channel = channel }
      return true
    end
    local ok, err = pcall(function()
      local setId = B.Create("Sounding", "melee_ranged")
      for i = 1, #B.Get(setId).bands do B.SetBandSound(setId, i, NS.Presets.OOR_SOUND) end
      opts = opts or {}
      opts.bandSet = setId
      opts.sounds = opts.sounds or { enabled = true, channel = "SFX" }
      local _, inst = H.container(opts.unit or "target", opts)
      body(played, inst, setId)
    end)
    M.PlaySoundFile, M.__now = savedPlay, savedNow
    if not ok then error(err, 0) end
  end)
end

--- A fresh unit behind the instance (its state forgotten), then its first band settled silently.
local function settledOn(inst, band, t)
  S.Reset(inst)
  S.OnBand(inst, band, t)
  S.OnBand(inst, band, t + S.SETTLE)
end

test("sounds: test_settle_200ms — a band's sound waits out the settle, then plays once", function()
  withSounds(function(played, inst)
    settledOn(inst, 1, 0)
    assertEqual(#played, 0, "the first band is silent")
    assertFalse(S.OnBand(inst, 2, 10), "entering a band plays nothing yet")
    assertFalse(S.OnBand(inst, 2, 10.19), "nor before 0.2 s")
    assertTrue(S.OnBand(inst, 2, 10.2), "at 0.2 s it plays")
    assertFalse(S.OnBand(inst, 2, 11), "and once")
    assertEqual(#played, 1)
    assertEqual(played[1].file, S.BUILTIN[NS.Presets.OOR_SOUND], "the built-in key resolves without LSM")
    assertEqual(played[1].channel, "SFX", "on the container's channel")
  end)
end)

test("sounds: a band left inside the settle never plays, and coming back to the settled one is quiet", function()
  withSounds(function(played, inst)
    settledOn(inst, 1, 0)
    S.OnBand(inst, 2, 5)
    S.OnBand(inst, 1, 5.1)        -- flickered out of band 1 and back inside the settle
    S.OnBand(inst, 1, 5.5)
    assertEqual(#played, 0, "band 2 never settled, and band 1 was already the settled band")
  end)
end)

test("sounds: test_gap_1s — a second band settling inside the gap is silent", function()
  withSounds(function(played, inst)
    settledOn(inst, 1, 0)
    S.OnBand(inst, 2, 10)
    S.OnBand(inst, 2, 10.2)
    assertEqual(#played, 1, "band 2 played")
    S.OnBand(inst, 3, 10.5)
    S.OnBand(inst, 3, 10.9)
    assertEqual(#played, 1, "band 3 settled 0.7 s after: inside the gap")
    S.OnBand(inst, 4, 11)
    S.OnBand(inst, 4, 11.2)
    assertEqual(#played, 2, "band 4 settled 1.0 s after the last sound: played")
  end)
end)

test("sounds: test_silent_first_band — the first band after a unit change is silent", function()
  withSounds(function(played, inst)
    settledOn(inst, 1, 0)
    S.OnBand(inst, 2, 5)
    S.OnBand(inst, 2, 5.3)
    assertEqual(#played, 1)
    -- A retarget: the renderer forgets the unit, so the new target's first band says nothing.
    NS.Container.UnitChanged("target")
    S.OnBand(inst, 4, 20)
    S.OnBand(inst, 4, 20.3)
    assertEqual(#played, 1, "the new unit's first band is silent")
    S.OnBand(inst, 5, 25)
    S.OnBand(inst, 5, 25.3)
    assertEqual(#played, 2, "its next band sounds")
    -- The unit going away counts as a change too: the next unit's first band is silent.
    S.OnBand(inst, "none", 30)
    S.OnBand(inst, "none", 30.3)
    S.OnBand(inst, 2, 31)
    S.OnBand(inst, 2, 31.3)
    assertEqual(#played, 2, "after no unit, the first band is silent")
  end)
end)

test("sounds: test_no_sound_for_nameplates — a nameplates container never sounds", function()
  withSounds(function(played)
    local plate = H.plate("nameplate1", true)
    assertTrue(plate ~= nil)
    H.added("nameplate1")
    local id = NS.CM.Create("nameplates", { sounds = { enabled = true } })
    NS.CM.FlushPending()
    local inst = NS.Container.GetPlate(id, "nameplate1")
    assertTrue(inst ~= nil, "the plate has an instance")
    assertFalse(S.Wants(inst), "a per-plate instance does not want sounds")
    settledOn(inst, 1, 0)
    S.OnBand(inst, 2, 5)
    S.OnBand(inst, 2, 6)
    assertEqual(#played, 0, "and plays none")
    assertEqual(inst.sound, nil, "nor keeps sound state")
  end)
end)

test("sounds: a container with sounds off, or a band with no sound, plays nothing", function()
  withSounds(function(played, inst, setId)
    B.SetBandSound(setId, 2, nil)
    settledOn(inst, 1, 0)
    S.OnBand(inst, 2, 5)
    S.OnBand(inst, 2, 6)
    assertEqual(#played, 0, "band 2 has no sound")
    inst.container.sounds.enabled = false
    S.OnBand(inst, 3, 10)
    S.OnBand(inst, 3, 11)
    assertEqual(#played, 0, "sounds off")
  end)
end)

test("sounds: a key LibSharedMedia does not know plays nothing, and a raising client is contained", function()
  withSounds(function(played, inst, setId)
    B.SetBandSound(setId, 2, "No such sound")
    settledOn(inst, 1, 0)
    S.OnBand(inst, 2, 5)
    S.OnBand(inst, 2, 6)
    assertEqual(#played, 0, "an unknown key")
    M.PlaySoundFile = function() error("blocked") end
    S.OnBand(inst, 3, 10)
    assertFalse(S.OnBand(inst, 3, 11), "a raise answers false, and nothing escapes")
  end)
end)

test("sounds: through the render path, a band change plays after the next steady read", function()
  withSounds(function(played, inst)
    local LRC = M.LibStub("LibRangeCheck-3.0", true)
    M.__now = 100
    NS.Ticker.Refresh("target")
    M.__now = 100.3
    NS.Ticker.Refresh("target")         -- the first band settles, silently
    assertEqual(#played, 0)
    LRC.GetRange = function() return 40, nil end
    M.__now = 101
    NS.Ticker.Refresh("target")          -- RANGE_UPDATED: into the out-of-range band
    assertEqual(#played, 0, "not before the settle")
    M.__now = 101.25
    NS.Ticker.Refresh("target")          -- a steady read (OnSteady) after the settle
    assertEqual(#played, 1, "the steady read plays it")
    assertEqual(inst.bandIndex, #NS.BandSets.Get(inst.setId).bands)
  end)
end)

test("sounds: a hidden container plays nothing", function()
  withSounds(function(played, inst)
    local LRC = M.LibStub("LibRangeCheck-3.0", true)
    inst.container.visibility.combat = "in"
    M.__now = 100
    NS.Ticker.Changed("target")
    assertFalse(inst.frame:IsShown())
    LRC.GetRange = function() return 40, nil end
    M.__now = 101
    NS.Ticker.Refresh("target")
    M.__now = 102
    NS.Ticker.Refresh("target")
    assertEqual(#played, 0)
  end)
end)

test("sounds: the out-of-range key the Advanced preset uses is built in", function()
  assertTrue(type(S.BUILTIN[NS.Presets.OOR_SOUND]) == "number", "a game sound file id")
end)
