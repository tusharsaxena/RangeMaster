-- tests/test_layers.lua — frame layering (frame-layering-§1..§5): the one LAYERS table, and no strata
-- literal or absolute level anywhere in the addon's own source. The range containers' own frames
-- join this suite with the renderer (the v0.1.0 plan, Task 5), read back through the kit's opt-in
-- frame-layer recorder (tests/_kit/mock_layers.lua).

local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local LAYERS = NS.Constants.LAYERS

-- ── the table ────────────────────────────────────────────────────────────────────────────────

test("LAYERS names the HUD strata and an ordered level ladder", function()
  assertEqual(type(LAYERS), "table", "NS.Constants.LAYERS is missing")
  assertEqual(LAYERS.STRATA.HUD, "MEDIUM")
  local L = LAYERS.LEVEL
  for _, k in ipairs({ "FILL", "BORDER", "OVERLAY", "HANDLE" }) do
    assertEqual(type(L[k]), "number", "LAYERS.LEVEL." .. k .. " is not a number")
  end
  -- frame-layering-§3: fill < border < overlay (text) < edit chrome at the top of the display.
  assertTrue(L.FILL < L.BORDER and L.BORDER < L.OVERLAY and L.OVERLAY < L.HANDLE,
    "the ladder must read FILL < BORDER < OVERLAY < HANDLE")
  assertTrue(L.FILL >= 1, "the fill sits above the container root's own background")
end)

-- ── the static half (frame-layering-§5) ──────────────────────────────────────────────────────

local function readFile(path)
  local fh = assert(io.open(path, "rb"))
  local body = fh:read("*a")
  fh:close()
  return body
end

test("no strata literal and no absolute level at any call site", function()
  for _, path in ipairs(T.loadedAddonFiles) do
    if path:match("^core/") or path:match("^modules/") or path:match("^settings/") then
      local body = readFile(path)
      assertFalse(body:find('SetFrameStrata%(%s*"') ~= nil,
        path .. " passes a strata literal; read NS.Constants.LAYERS.STRATA")
      assertFalse(body:find("SetFrameLevel%(%s*%d") ~= nil,
        path .. " sets an absolute frame level; use base:GetFrameLevel() + LAYERS.LEVEL.<NAME>")
    end
  end
end)
