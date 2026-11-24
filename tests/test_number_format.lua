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

test("number: a dead-zone band pulls the far bound in to the ranged anchor's min (5-10 reads 5-8)", function()
  -- red under: the bracket written as LibRangeCheck gives it (the owner, 2026-11-24: a Forever
  -- hunter's DEAD read 5-10, though Auto Shot's false already puts the target inside 8 yd).
  local BracketOf = NS.Elements.Number.BracketOf
  local savedAnchor = NS.Range.Anchor
  NS.Range.Anchor = function(role) if role == "ranged" then return { id = 75, minRange = 8, maxRange = 35 } end end
  local ok, err = pcall(function()
    local gap = { from = 5, to = 8, rule = { type = "gap" } }
    local lo, hi = BracketOf({ state = "known", lo = 5, hi = 10, row = gap })
    assertEqual(Format("range", "known", lo, hi, "?"), "5" .. DASH .. "8", "DEAD: 5-8")
    local _, hi2 = BracketOf({ state = "known", lo = 5, hi = 8, row = gap })
    assertEqual(hi2, 8, "a bracket already inside stays")
    local _, hi3 = BracketOf({ state = "known", lo = 5, hi = 10, row = { from = 0, to = 5, rule = { type = "spell", role = "melee" } } })
    assertEqual(hi3, 10, "any other band writes the bracket as it is")
    NS.Range.Anchor = function() return nil end
    local _, hi4 = BracketOf({ state = "known", lo = 5, hi = 10, row = gap })
    assertEqual(hi4, 8, "no ranged anchor: the band's own edge")
  end)
  NS.Range.Anchor = savedAnchor
  if not ok then error(err, 0) end
end)
