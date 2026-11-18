-- tests/test_number_format.lua — the number element's six formats (modules/Elements_Number.lua,
-- NS.Elements.Number.Format). The v0.1.0 plan, Task 5; design spec section 5.3 ("Number formats").
--
-- The engine answers a BRACKET, never a distance, so every format is a way of writing that bracket
-- down: an open-ended one reads "40+" whatever the format, and an unknown one reads the band set's
-- unknown label. No format may invent a figure the bracket does not hold.

local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual = T.test, T.assertEqual

local Format = NS.Elements.Number.Format
local DASH = "\226\128\147"   -- the en dash a range is written with

test("number: the six formats on the bracket (20, 25)", function()
  assertEqual(Format("range", "known", 20, 25, "?"), "20" .. DASH .. "25")
  assertEqual(Format("max", "known", 20, 25, "?"), "25")
  assertEqual(Format("min", "known", 20, 25, "?"), "20")
  assertEqual(Format("under", "known", 20, 25, "?"), "<25")
  assertEqual(Format("approx", "known", 20, 25, "?"), "~22", "the floor of the midpoint, 22.5")
  assertEqual(Format("suffix", "known", 20, 25, "?"), "25 yd")
end)

test("number: an open-ended bracket reads 40+ in every format, never an invented far bound", function()
  for _, fmt in ipairs({ "range", "max", "min", "under", "approx", "suffix" }) do
    assertEqual(Format(fmt, "known", 40, nil, "?"), "40+", fmt)
  end
end)

test("number: an unknown range reads the band set's unknown label in every format", function()
  for _, fmt in ipairs({ "range", "max", "min", "under", "approx", "suffix" }) do
    assertEqual(Format(fmt, "unknown", nil, nil, "?"), "?", fmt)
  end
  assertEqual(Format("range", "unknown", nil, nil, "--"), "--", "the set's own label, not a literal")
  assertEqual(Format("range", "unknown", nil, nil, nil), "?", "no label given reads the default")
end)

test("number: no unit reads nothing, and an unknown format reads as range", function()
  assertEqual(Format("range", "none", nil, nil, "?"), "")
  assertEqual(Format("bogus", "known", 20, 25, "?"), "20" .. DASH .. "25")
  assertEqual(Format(nil, "known", 0, 5, "?"), "0" .. DASH .. "5", "the closest rung starts at 0")
end)

test("number: a known state with no far bound and no near bound reads unknown, not 0", function()
  assertEqual(Format("max", "known", nil, nil, "?"), "?")
end)
