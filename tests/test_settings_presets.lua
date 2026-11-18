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
