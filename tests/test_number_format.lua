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

test("number: every format writes the bracket trimmed to the drawn band's span (the owner, 2026-11-24)", function()
  -- red under: the bracket written as LibRangeCheck gives it (a Forever hunter's DEAD read 0-5 and
  -- 5-10, AUTO 5-10, About ~7 in the dead zone; only Band span agreed with the band).
  local BracketOf = NS.Elements.Number.BracketOf
  local savedFor = NS.Range.AnchorFor
  NS.Range.AnchorFor = function(role)
    if role == "melee" then return { id = 2974, minRange = 0, maxRange = 5 } end
    if role == "ranged" then return { id = 75, minRange = 8, maxRange = 41 } end
  end
  local ok, err = pcall(function()
    local set = { bands = {
      { from = 0, to = 5, rule = { type = "spell", role = "melee" } },
      { from = 5, to = 8, rule = { type = "gap" } },
      { from = 8, to = 35, rule = { type = "spell", role = "ranged" } },
      { from = 35, rule = { type = "beyond" } },
    } }
    local function write(fmt, band, lo, hi)
      local blo, bhi = BracketOf({ state = "known", lo = lo, hi = hi, set = set, band = band })
      return Format(fmt, "known", blo, bhi, "?")
    end
    assertEqual(write("range", 3, 5, 10), "8" .. DASH .. "10", "AUTO at 5-10: 8-10")
    assertEqual(write("range", 2, 0, 5), "5" .. DASH .. "8", "DEAD at 0-5: no overlap, the band's span")
    assertEqual(write("range", 2, 5, 10), "5" .. DASH .. "8", "DEAD at 5-10: 5-8")
    assertEqual(write("approx", 2, 5, 10), "~6", "About in the dead zone stays inside it")
    assertEqual(write("range", 1, 0, 5), "0" .. DASH .. "5", "MELEE at 0-5 stays")
    assertEqual(write("range", 3, 20, 25), "20" .. DASH .. "25", "a bracket inside its band stays")
    assertEqual(write("range", 4, 35, 40), "41+", "OOR past Auto Shot's 41 yd: the beyond span")
    assertEqual(write("range", 4, 45, nil), "45+", "an open bracket past the reach stays")
    local blo, bhi = BracketOf({ state = "unknown", set = set, band = "unknown" })
    assertEqual(blo, nil, "unknown: untouched")
    assertEqual(bhi, nil)
  end)
  NS.Range.AnchorFor = savedFor
  if not ok then error(err, 0) end
end)
