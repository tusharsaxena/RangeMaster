-- tests/test_skin_picker_preview.lua — the skin picker's eye on this addon's seam (skinning-§10;
-- core/SkinSetup.lua, LibKa0s OptionsSkinPicker minor 11's spec.preview).
--
-- The picker previews in TEST MODE, the mode the roster row names. When the picker shows with Test
-- mode off, Test mode turns on; the eye toggles it; every close puts back the state the picker opened
-- with. Each switch goes through NS.SetTestMode, the one writer the Master controls checkbox, `/rm
-- test` and the launcher use, so a start in combat is refused there and the eye adds no path round it.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function quietly(fn)
  local cf = M.DEFAULT_CHAT_FRAME
  local old = rawget(cf, "AddMessage")
  cf.AddMessage = function() end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err, 0) end
end

local function testMode() return NS.State.testMode == true end

--- A clean start: no picker up, Test mode off, out of combat.
local function reset()
  quietly(function()
    NS.HideSkinPicker()
    NS.EndModes("test reset")
  end)
  M.InCombatLockdown = function() return false end
end

--- The real picker, shown by `/rm skin`.
local function shownPicker()
  local f
  quietly(function() f = NS.RunSkinVerb() end)
  assertTrue(f ~= nil and f:IsShown(), "the library's picker did not show")
  return f
end

--- Every NS.SetTestMode call from now on, as "on:why" or "off:why"; returns the list and a restore.
local function spySeam()
  local calls, live = {}, NS.SetTestMode
  NS.SetTestMode = function(on, why)
    calls[#calls + 1] = (on and "on" or "off") .. ":" .. tostring(why)
    return live(on, why)
  end
  return calls, function() NS.SetTestMode = live end
end

test("Skin preview: the spec hands the picker spec.preview in test mode", function()
  local spec = NS.SkinPickerSpec()
  local pv = spec.preview
  assertTrue(type(pv) == "table", "the eye is spec.preview, the library's preview contract")
  assertEqual(pv.mode, "test", "this addon previews in its Test mode (the roster row's `test`)")
  for _, k in ipairs({ "enter", "exit", "isActive" }) do
    assertEqual(type(pv[k]), "function", "spec.preview." .. k)
  end
  assertEqual(spec.onPreview, nil, "no one-shot enter-only eye")
end)

test("Skin preview: opened with Test mode off, Test mode turns on through the one writer", function()
  reset()
  local calls, restore = spySeam()
  local f = shownPicker()
  restore()
  assertTrue(testMode(), "the picker opened and Test mode stayed off")
  assertEqual(table.concat(calls, ","), "on:skin picker", "one start, through NS.SetTestMode")
  assertTrue(f.preview.lit == true, "the eye is lit while Test mode is on")
  reset()
end)

test("Skin preview: the eye toggles Test mode", function()
  reset()
  local f = shownPicker()
  quietly(function() f.preview:__fire("OnClick") end)
  assertFalse(testMode(), "the eye did not turn Test mode off")
  quietly(function() f.preview:__fire("OnClick") end)
  assertTrue(testMode(), "the eye did not turn Test mode back on")
  reset()
end)

local ROUTES = {
  { "the close control", function(f) f.close:__fire("OnClick") end },
  { "Escape", function(f) f:Hide(); f:__fire("OnHide") end },
  { "Apply", function(f) f.apply:__fire("OnClick") end },
  { "HideSkinPicker", function() NS.HideSkinPicker() end },
}

for _, route in ipairs(ROUTES) do
  test("Skin preview: closing by " .. route[1] .. " turns off the Test mode it turned on", function()
    -- red under: no restore, so Test mode stayed on after the picker closed.
    reset()
    local f = shownPicker()
    assertTrue(testMode())
    quietly(function() route[2](f) end)
    assertFalse(f:IsShown(), route[1] .. " left the picker up")
    assertFalse(testMode(), route[1] .. " left Test mode on")
    reset()
  end)
end

test("Skin preview: a Test mode already on is left alone by the close", function()
  reset()
  quietly(function() NS.SetTestMode(true, "/rm test") end)
  local calls, restore = spySeam()
  local f = shownPicker()
  restore()
  assertEqual(#calls, 0, "a Test mode already on was entered again")
  quietly(function() f.close:__fire("OnClick") end)
  assertTrue(testMode(), "the close stopped the player's own Test mode")
  reset()
end)

test("Skin preview: the eye in combat starts nothing, and the close undoes nothing", function()
  reset()
  local f = shownPicker()
  quietly(function() f.preview:__fire("OnClick") end)
  assertFalse(testMode())
  M.InCombatLockdown = function() return true end
  quietly(function() f.preview:__fire("OnClick") end)
  assertFalse(testMode(), "the eye started Test mode in combat")
  quietly(function() f.close:__fire("OnClick") end)
  M.InCombatLockdown = function() return false end
  assertFalse(testMode(), "the close started Test mode")
  reset()
end)
