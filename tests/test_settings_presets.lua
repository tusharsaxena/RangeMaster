-- tests/test_settings_presets.lua — the presets' surfaces (settings/Presets.lua): the confirm every
-- Apply takes, the Undo, the General page's Presets tab and the first-run picker. The v0.1.0 plan,
-- Task 8; design spec sections 5.2 and 5.6.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local E = dofile("tests/settings_env.lua")
local CM, Presets = NS.CM, NS.Presets

--- The units of the containers, in order, joined.
local function units()
  local out = {}
  for i, id in ipairs(CM.List()) do out[i] = CM.Get(id).unit end
  return table.concat(out, ",")
end

test("presets: test_preset_apply_confirms — Apply asks first when there is something to replace, and Undo puts it back", function()
  E.with(function()
    local shown = E.spyPopups()
    CM.Create("pet")
    local answer
    E.capture(function() answer = NS.ConfirmPreset("simple") end)
    assertEqual(answer, "shown", "a profile with containers is asked first")
    assertEqual(#shown, 1)
    assertEqual(shown[1].which, "RANGEMASTER_APPLY_PRESET")
    assertEqual(shown[1].a, "Simple", "the confirm names the preset")
    assertEqual(shown[1].b, 1, "and the count it replaces")
    assertEqual(units(), "pet", "nothing changes before the answer")
    local out = E.capture(function() E.accept(shown[1]) end)
    assertEqual(units(), "target,focus,pet,mouseover", "the answer applies the preset it named")
    assertTrue(E.said(out, "Simple preset applied"), "and says so")
    assertTrue(Presets.CanUndo())
    E.capture(function() assertTrue(NS.UndoPreset()) end)
    assertEqual(units(), "pet", "Undo puts back what was there")
    local again = E.capture(function() assertFalse(NS.UndoPreset()) end)
    assertTrue(E.said(again, "No preset to undo"), "one level: a second Undo says there is none")
  end)
end)

test("presets: an empty profile applies at once, with nothing to confirm", function()
  E.with(function()
    local shown = E.spyPopups()
    local answer
    E.capture(function() answer = NS.ConfirmPreset("intermediate") end)
    assertEqual(answer, "applied")
    assertEqual(#shown, 0, "no confirm: nothing of the player's is replaced")
    assertEqual(#CM.List(), 4)
    assertFalse(Presets.PickerDue(), "applying a preset marks the first-run picker seen")
    assertEqual(NS.ConfirmPreset("bogus"), nil, "an unknown key does nothing")
  end)
end)

test("presets: test_first_run_picker_once — the picker shows once per profile, marks it seen as it shows, and waits out combat", function()
  E.with(function(p)
    local shown = E.spyPopups()
    assertEqual(p.seeded, false, "a fresh profile owes the picker")
    assertTrue(NS.MaybeShowPresetPicker(), "it shows")
    assertEqual(#shown, 1)
    assertEqual(shown[1].which, "RANGEMASTER_PRESET_PICKER")
    assertEqual(p.seeded, true, "marked seen as it shows: a /reload never offers it again")
    assertFalse(NS.MaybeShowPresetPicker(), "a second ask shows nothing")
    assertEqual(#shown, 1)

    p.seeded = false
    M.InCombatLockdown = function() return true end
    assertTrue(NS.MaybeShowPresetPicker(), "in combat it is held, which keeps the skin picker back too")
    assertEqual(#shown, 1, "nothing shows in combat")
    assertTrue(NS.__presetPickerHeld())
    M.InCombatLockdown = function() return false end
    M.__fireEvent("PLAYER_REGEN_ENABLED")
    assertEqual(#shown, 2, "combat ending shows it")
    assertFalse(NS.__presetPickerHeld())
    assertEqual(p.seeded, true)
  end)
end)

--- Stand in for the client's StaticPopup_Hide, which runs the dialog's OnHide as it closes it.
local function withClientHide(body)
  local saved = rawget(M, "StaticPopup_Hide")
  M.StaticPopup_Hide = function(which)
    local d = M.StaticPopupDialogs[which]
    if d and d.OnHide then d.OnHide() end
  end
  local ok, err = pcall(body)
  M.StaticPopup_Hide = saved
  if not ok then error(err, 0) end
end

--- Count NS.MaybeShowSkinPicker calls while `body` runs (the picker itself is not shown).
local function countSkinAsks(body)
  local saved, n = NS.MaybeShowSkinPicker, 0
  NS.MaybeShowSkinPicker = function() n = n + 1 end
  local ok, err = pcall(body)
  NS.MaybeShowSkinPicker = saved
  if not ok then error(err, 0) end
  return n
end

test("presets: taking the picker down offers no skin picker; the player's close does", function()
  E.with(function()
    E.spyPopups()
    withClientHide(function()
      assertEqual(countSkinAsks(function() NS.HidePresetPicker() end), 0,
        "the stand-down and a profile event close it quietly")
      assertEqual(countSkinAsks(function() M.StaticPopupDialogs.RANGEMASTER_PRESET_PICKER.OnHide() end), 1,
        "Not now, Escape or Choose a preset offers the skin picker next")
    end)
  end)
end)

test("presets: a profile change while the picker is up shows only the new profile's preset picker", function()
  E.with(function(p)
    local shown = E.spyPopups()
    assertTrue(NS.MaybeShowPresetPicker())
    local other = {}
    NS.Database.PrepareProfile(other)
    NS.db.profile = other
    withClientHide(function()
      local asks = countSkinAsks(function() NS.OnProfileChanged() end)
      assertEqual(asks, 0, "the skin picker waits behind the new profile's preset picker")
    end)
    assertEqual(#shown, 2, "the new profile's preset picker showed")
    assertEqual(shown[2].which, "RANGEMASTER_PRESET_PICKER")
    NS.db.profile = p
  end)
end)

test("presets: the picker's Choose a preset opens the General page on its Presets tab", function()
  E.with(function()
    local opened
    local saved = NS.OpenOptionsPanel
    NS.OpenOptionsPanel = function(key) opened = key; return true end
    local ok, err = pcall(function()
      M.StaticPopupDialogs.RANGEMASTER_PRESET_PICKER.OnAccept()
      assertEqual(opened, "general", "the General page")
      local ctx = E.page("general", "General")
      assertEqual(ctx.activeTab, "Presets", "on its Presets tab")
    end)
    NS.OpenOptionsPanel = saved
    NS.__generalTab = nil
    if not ok then error(err, 0) end
  end)
end)

test("presets: the Presets tab draws the three cards with Apply and the Undo button", function()
  E.with(function()
    local ctx = E.page("general", "General")
    ctx.activeTab = "Presets"
    NS.Helpers.RefreshPanel(ctx, true)
    local labels = E.labels(ctx)
    for _, text in ipairs({ "Apply Simple\226\128\166", "Apply Intermediate\226\128\166", "Apply Advanced\226\128\166",
        "Undo last preset" }) do
      assertTrue(labels[text], "the tab carries " .. text)
    end
    ctx.activeTab = "Master controls"
    NS.Helpers.RefreshPanel(ctx, true)
  end)
end)
