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

-- ── the range container's stack (frame-layering-§3) ───────────────────────────────────────────

test("a range container's root sits in the HUD strata, its fill, border and overlay offset over it", function()
  local M = T.mocks
  local restore = dofile("tests/_kit/mock_layers.lua")(M)
  local savedDb = NS.db
  NS.db = { profile = {}, global = savedDb.global }
  NS.CM.__reset()
  NS.Container.__reset()
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(NS.db.profile)
    local id = NS.CM.Create("target")
    NS.CM.FlushPending()
    local inst = NS.Container.Get(id)
    local rootLevel = M.__layers(inst.frame).level
    assertEqual(M.__layers(inst.frame).strata, LAYERS.STRATA.HUD, "the stored MEDIUM is the HUD band")
    assertEqual(M.__layers(inst.fill).level, rootLevel + LAYERS.LEVEL.FILL, "fill")
    assertEqual(M.__layers(inst.border.frame).level, rootLevel + LAYERS.LEVEL.BORDER, "border")
    assertEqual(M.__layers(inst.overlay).level, rootLevel + LAYERS.LEVEL.OVERLAY, "overlay")
  end)
  NS.Container.__reset()
  NS.CM.__reset()
  NS.db = savedDb
  restore()
  if not ok then error(err, 0) end
end)

test("overlapping range containers stack whole: each root has its own base, a stride apart", function()
  -- red under: every root left at UIParent's level + 1 (one display's overlay above the next one's
  -- fill: crowded nameplates and the cursor display interleave). frame-layering-§3, Peers stack whole.
  local M = T.mocks
  local restore = dofile("tests/_kit/mock_layers.lua")(M)
  local savedDb = NS.db
  NS.db = { profile = {}, global = savedDb.global }
  NS.CM.__reset()
  NS.Container.__reset()
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(NS.db.profile)
    local a, b = NS.CM.Create("target"), NS.CM.Create("focus")
    NS.CM.FlushPending()
    local la = M.__layers(NS.Container.Get(a).frame).level
    local lb = M.__layers(NS.Container.Get(b).frame).level
    local L = LAYERS.LEVEL
    assertTrue(type(L.STRIDE) == "number" and L.STRIDE > L.HANDLE,
      "the stride covers a whole display's band, the drag handle included")
    assertTrue(math.abs(la - lb) >= L.STRIDE, ("two roots a stride apart (got %d and %d)"):format(la, lb))
    assertTrue(math.max(la, lb) + L.HANDLE < 10000, "under the client's frame-level ceiling")
  end)
  NS.Container.__reset()
  NS.CM.__reset()
  NS.db = savedDb
  restore()
  if not ok then error(err, 0) end
end)

test("a hand-edited dialog strata draws in the HUD band: the renderer takes only the row's values", function()
  -- red under: a renderer whitelist wider than settings/Containers.lua's V.STRATA (DIALOG and up
  -- are no HUD tier, frame-layering-§1).
  local M = T.mocks
  local restore = dofile("tests/_kit/mock_layers.lua")(M)
  local savedDb = NS.db
  NS.db = { profile = {}, global = savedDb.global }
  NS.CM.__reset()
  NS.Container.__reset()
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(NS.db.profile)
    local id = NS.CM.Create("target")
    local c = NS.CM.Get(id)
    c.anchor.strata = "DIALOG"
    NS.CM.FlushPending()
    assertEqual(M.__layers(NS.Container.Get(id).frame).strata, LAYERS.STRATA.HUD, "DIALOG falls back")
    c.anchor.strata = "HIGH"
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    assertEqual(M.__layers(NS.Container.Get(id).frame).strata, "HIGH", "an offered value is kept")
  end)
  NS.Container.__reset()
  NS.CM.__reset()
  NS.db = savedDb
  restore()
  if not ok then error(err, 0) end
end)
