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
    E.capture(function() answer = NS.ConfirmPreset("text") end)
    assertEqual(answer, "applied")
    assertEqual(#shown, 0, "no confirm: nothing of the player's is replaced")
    assertEqual(#CM.List(), 4)
    assertFalse(Presets.PickerDue(), "applying a preset marks the first-run picker seen")
    assertEqual(NS.ConfirmPreset("bogus"), nil, "an unknown key does nothing")
  end)
end)

local P = NS.PresetPicker

--- Run `body(p, C)` on a fresh profile with the picker's controls `C`; the window is taken down
--- quietly however the case ends, and test mode and the lock put back.
local function withPicker(body)
  E.with(function(p)
    local ok, err = pcall(body, p, P.__controls)
    E.capture(function() NS.HidePresetPicker() end)
    NS.SetTestMode(false, "suite")
    if not ok then error(err, 0) end
  end)
end

local function shownNow() return P.frame ~= nil and P.frame:IsShown() == true end

--- Count NS.MaybeShowSkinPicker calls while `body` runs (the picker itself is not shown).
local function countSkinAsks(body)
  local saved, n = NS.MaybeShowSkinPicker, 0
  NS.MaybeShowSkinPicker = function() n = n + 1 end
  local ok, err = pcall(body)
  NS.MaybeShowSkinPicker = saved
  if not ok then error(err, 0) end
  return n
end

test("presets: test_first_run_picker_once — the picker shows once per profile, marks it seen as it shows, and waits out combat", function()
  withPicker(function(p)
    assertEqual(p.seeded, false, "a fresh profile owes the picker")
    assertTrue(NS.MaybeShowPresetPicker(), "it shows")
    assertTrue(shownNow(), "the window is up")
    assertEqual(p.seeded, true, "marked seen as it shows: a /reload never offers it again")
    assertFalse(NS.MaybeShowPresetPicker(), "a second ask shows nothing")
    E.capture(function() NS.HidePresetPicker() end)

    p.seeded = false
    M.InCombatLockdown = function() return true end
    assertTrue(NS.MaybeShowPresetPicker(), "in combat it is held, which keeps the skin picker back too")
    assertFalse(shownNow(), "nothing shows in combat")
    assertTrue(NS.__presetPickerHeld())
    assertTrue(NS.PresetPickerHolding())
    M.InCombatLockdown = function() return false end
    M.__fireEvent("PLAYER_REGEN_ENABLED")
    assertTrue(shownNow(), "combat ending shows it")
    assertFalse(NS.__presetPickerHeld())
    assertEqual(p.seeded, true)
  end)
end)

test("presets: the picker opens unlocked in test mode, a pick previews, and Not now restores", function()
  withPicker(function(_, C)
    CM.Create("pet")
    NS.SetByPath("locked", true)
    NS.MaybeShowPresetPicker()
    assertFalse(NS.GetSetting("locked"), "opening unlocks the containers")
    assertTrue(NS.IsTestMode(), "and turns test mode on")
    assertEqual(units(), "pet", "nothing is previewed until a pick")
    C.pick("expert")
    assertEqual(#CM.List(), 6, "a pick puts the preset on the screen")
    assertEqual(Presets.Previewed(), "expert")
    C.pick("simple")
    assertEqual(units(), "target,focus,pet,mouseover", "a second pick swaps the preview")
    local asks = countSkinAsks(function() E.capture(function() C.dismiss() end) end)
    assertFalse(shownNow(), "Not now closes it")
    assertEqual(units(), "pet", "and puts the player's own containers back")
    assertFalse(NS.IsTestMode(), "test mode goes off")
    assertTrue(NS.GetSetting("locked"), "the lock the window found goes back")
    assertEqual(asks, 1, "the skin picker is offered next")
    assertFalse(Presets.CanUndo(), "a preview never kept leaves nothing to undo")
  end)
end)

test("presets: the picker's Apply asks over the player's containers, keeps the pick and locks", function()
  withPicker(function(_, C)
    local shown = E.spyPopups()
    CM.Create("pet")
    NS.MaybeShowPresetPicker()
    C.pick("simple")
    C.apply()
    assertEqual(#shown, 1, "the player has a container to lose: asked first")
    assertEqual(shown[1].which, "RANGEMASTER_APPLY_PRESET")
    assertEqual(shown[1].a, "Simple")
    assertEqual(shown[1].b, 1, "the count is the player's own, not the preview's")
    assertTrue(shownNow(), "the window stays up under the confirm")
    local out = E.capture(function() countSkinAsks(function() E.accept(shown[1]) end) end)
    assertTrue(E.said(out, "Simple preset applied"), "the answer keeps the pick")
    assertFalse(shownNow(), "and closes the window")
    assertEqual(units(), "target,focus,pet,mouseover")
    assertTrue(NS.GetSetting("locked"), "Apply locks")
    assertFalse(NS.IsTestMode(), "and turns test mode off")
    E.capture(function() assertTrue(NS.UndoPreset()) end)
    assertEqual(units(), "pet", "Undo puts back what was there before the picker")
  end)
end)

test("presets: test_picker_lists_six — the picker's dropdown offers the six presets, each pick previewed with its blurb", function()
  -- red under: the three-preset dropdown (simple, intermediate, advanced).
  withPicker(function()
    NS.MaybeShowPresetPicker()
    local values, labels = {}, {}
    for i, o in ipairs(P.frame.dd._options or {}) do values[i], labels[i] = o.value, o.label end
    assertEqual(table.concat(values, ","), "simple,text,numbers,advanced,expert,ka0s")
    assertEqual(labels[6], "Ka0s - 5 containers")
    assertEqual(labels[2], "Intermediate (Range Text) - 4 containers")
    assertEqual(labels[3], "Intermediate (Range Numbers) - 4 containers")
    assertEqual(labels[5], "Expert - 6 containers")
    -- The kit's font strings may not answer GetText: the blurb is captured as it is set.
    local fs, blurb = P.frame.blurb, nil
    local setText = fs.SetText
    fs.SetText = function(self, text, ...) blurb = text; if setText then return setText(self, text, ...) end end
    local blurbs = {}
    local ok, err = pcall(function()
      for _, key in ipairs(Presets.ORDER) do
        blurb = nil
        P.__controls.pick(key)
        assertEqual(Presets.Previewed(), key, key .. " previews")
        assertEqual(#CM.List(), Presets.Describe(key).count, key .. ": its containers on screen")
        assertTrue(type(blurb) == "string" and blurb ~= "", key .. " has a blurb")
        assertTrue(blurbs[blurb] == nil, key .. "'s blurb is its own")
        blurbs[blurb] = true
      end
    end)
    fs.SetText = setText
    if not ok then error(err, 0) end
  end)
end)

test("presets: test_picker_previews_on_empty_profile — a new profile's picker puts Simple on screen as it opens", function()
  -- red under: a picker that previews nothing until a pick (an empty screen under the window).
  withPicker(function(_, C)
    NS.MaybeShowPresetPicker()
    assertEqual(units(), "target,focus,pet,mouseover", "Simple, the selection, is on screen")
    assertEqual(Presets.Previewed(), "simple")
    C.pick("expert")
    assertEqual(#CM.List(), 6, "a pick swaps it as before")
    E.capture(function() C.dismiss() end)
    assertEqual(#CM.List(), 0, "Not now leaves the profile empty again")
  end)
end)

test("presets: Apply over an empty profile keeps the pick at once; with no pick it keeps what is there", function()
  withPicker(function(_, C)
    local shown = E.spyPopups()
    NS.MaybeShowPresetPicker()
    C.pick("numbers")
    E.capture(function() C.apply() end)
    assertEqual(#shown, 0, "nothing of the player's is replaced: no confirm")
    assertEqual(#CM.List(), 4)
    assertFalse(shownNow())

    NS.ShowPresetPicker()
    assertTrue(shownNow(), "/rm preset opens it on demand")
    E.capture(function() C.apply() end)
    assertEqual(#CM.List(), 4, "Apply with nothing picked keeps the profile as it is")
    assertFalse(shownNow())
  end)
end)

test("presets: taking the picker down offers no skin picker and restores; a replaced profile is not restored", function()
  withPicker(function(_, C)
    CM.Create("pet")
    NS.MaybeShowPresetPicker()
    C.pick("expert")
    assertEqual(countSkinAsks(function() E.capture(function() NS.HidePresetPicker() end) end), 0,
      "the stand-down and a profile event close it quietly")
    assertEqual(units(), "pet", "its preview restored")

    NS.ShowPresetPicker()
    C.pick("simple")
    E.capture(function() NS.HidePresetPicker(true) end)
    assertFalse(Presets.IsPreviewing(), "a reset or a copy drops the preview")
    assertEqual(#CM.List(), 4, "without writing the old set over the replacement")
  end)
end)

test("presets: Escape is the player's close; the settings mark closes it and opens General > Presets", function()
  withPicker(function(_, C)
    NS.MaybeShowPresetPicker()
    local asks = countSkinAsks(function()
      E.capture(function()
        P.frame:Hide()
        P.frame:GetScript("OnHide")(P.frame)
      end)
    end)
    assertEqual(asks, 1, "Escape (UISpecialFrames) offers the skin picker next")

    local opened
    local saved = NS.OpenOptionsPanel
    NS.OpenOptionsPanel = function(key) opened = key; return true end
    local ok, err = pcall(function()
      NS.ShowPresetPicker()
      C.pick("simple")
      assertEqual(countSkinAsks(function() E.capture(function() C.settings() end) end), 0,
        "no skin picker over the panel")
      assertFalse(shownNow())
      assertEqual(#CM.List(), 0, "the preview is restored")
      assertEqual(opened, "general", "the General page")
      local ctx = E.page("general", "General")
      assertEqual(ctx.activeTab, "Presets", "on its Presets tab")
    end)
    NS.OpenOptionsPanel = saved
    NS.__generalTab = nil
    if not ok then error(err, 0) end
  end)
end)

test("presets: combat starting restores a preview, and a pick in combat is refused", function()
  withPicker(function(_, C)
    CM.Create("pet")
    NS.MaybeShowPresetPicker()
    C.pick("expert")
    NS.PresetPickerCombat()
    assertEqual(units(), "pet", "the player's set is back for the fight")
    assertTrue(shownNow(), "the window stays up")
    M.InCombatLockdown = function() return true end
    local out = E.capture(function() C.pick("simple") end)
    assertTrue(E.said(out, "cannot preview a preset during combat"))
    assertEqual(units(), "pet")
    M.InCombatLockdown = function() return false end
  end)
end)

test("presets: a profile change while the picker is up shows only the new profile's preset picker", function()
  withPicker(function(p)
    NS.MaybeShowPresetPicker()
    local other = {}
    NS.Database.PrepareProfile(other)
    NS.db.profile = other
    local asks = countSkinAsks(function() E.capture(function() NS.OnProfileChanged() end) end)
    assertEqual(asks, 0, "the skin picker waits behind the new profile's preset picker")
    assertTrue(shownNow(), "the new profile's preset picker showed")
    assertEqual(other.seeded, true)
    NS.db.profile = p
  end)
end)

test("presets: test_presets_tab_five — the Presets tab draws the five cards with Apply and the Undo button", function()
  -- red under: the tab's three cards (Simple, Intermediate, Advanced).
  E.with(function()
    local ctx = E.page("general", "General")
    ctx.activeTab = "Presets"
    NS.Helpers.RefreshPanel(ctx, true)
    local labels = E.labels(ctx)
    for _, text in ipairs({ "Apply Simple\226\128\166", "Apply Intermediate (Range Text)\226\128\166",
        "Apply Intermediate (Range Numbers)\226\128\166", "Apply Advanced\226\128\166", "Apply Expert\226\128\166",
        "Expert \194\183 6 containers", "Advanced \194\183 4 containers", "Undo last preset" }) do
      assertTrue(labels[text], "the tab carries " .. text)
    end
    ctx.activeTab = "Master controls"
    NS.Helpers.RefreshPanel(ctx, true)
  end)
end)

test("presets: test_unlock_with_nothing_says_so — /rm unlock on an empty profile points at /rm preset; with containers it shows them", function()
  -- red under: an unlock that shows nothing and says nothing on a profile with no containers.
  E.with(function()
    local out = E.capture(function() NS.Slash:OnSlash("unlock") end)
    assertTrue(table.concat(out, "\n"):find("/rm preset", 1, true) ~= nil, "an empty profile is told how to get some")
    NS.SetByPath("locked", true)
    Presets.Apply("simple")
    CM.FlushPending()
    out = E.capture(function() NS.Slash:OnSlash("unlock") end)
    assertTrue(table.concat(out, "\n"):find("/rm preset", 1, true) == nil, "no hint once it has containers")
    for _, id in ipairs(CM.List()) do
      local inst = NS.Container.Get(id)
      assertTrue(inst ~= nil and inst.frame:IsShown(), CM.Get(id).name .. " shows unlocked")
      assertTrue(inst.dragHandle ~= nil and inst.dragHandle:IsShown(), CM.Get(id).name .. " wears its drag strip")
    end
    NS.SetByPath("locked", true)
  end)
end)
