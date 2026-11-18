-- tests/test_container_render.lua — the renderer (modules/Container.lua, NS.Container, with the
-- element files and modules/Style.lua): one pooled instance per enabled container, its elements built
-- on demand and laid out by `elements.order`, text set only when it changes, colors set only when
-- the band does. The v0.1.0 plan, Task 5; design spec section 5.3.
--
-- Every case runs on a FRESH profile with the kit's paint recorder installed (tests/_kit/
-- mock_paint.lua: textures and font strings that remember what they were told), so the instance's
-- regions are distinct objects a spy can be laid on. The renderer's pool is dropped before and after,
-- so every case builds its own frames under the recorder.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local CM, B, Container = NS.CM, NS.BandSets, NS.Container
local C = NS.Constants
local installPaint = dofile("tests/_kit/mock_paint.lua")

local function withRenderer(body, classToken)
  local savedDb, savedClass, savedFriend = NS.db, M.__context.classToken, M.UnitIsFriend
  local LRC = M.LibStub("LibRangeCheck-3.0", true)
  local savedGet, hadTarget = LRC.GetRange, M.__unitExists.target
  if classToken then M.__context.classToken = classToken end
  local restorePaint = installPaint(M)
  local p = {}
  NS.db = { profile = p, global = savedDb.global }
  CM.__reset()
  Container.__reset()
  LRC.GetRange = function() return 20, 25 end
  M.__unitExists.target = true
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(p)
    body(p, LRC)
  end)
  Container.__reset()
  CM.__reset()
  restorePaint()
  NS.db = savedDb
  M.__context.classToken, M.UnitIsFriend = savedClass, savedFriend
  LRC.GetRange, M.__unitExists.target = savedGet, hadTarget
  if not ok then error(err, 0) end
end

--- A target container on a fresh Melee / Ranged set, applied (the next frame's flush run now).
local function newContainer(opts)
  local setId = B.Create("Test bands", "melee_ranged")
  opts = opts or {}
  opts.bandSet = opts.bandSet or setId
  local id = CM.Create(opts.unit or "target", opts)
  CM.FlushPending()
  return id, setId, Container.Get(id)
end

--- Count calls of `method` on `obj` while `fn` runs; the method still runs.
local function count(obj, method, fn)
  local real, raw, n = obj[method], rawget(obj, method), 0
  rawset(obj, method, function(...) n = n + 1; return real(...) end)
  local ok, err = pcall(fn)
  rawset(obj, method, raw)
  if not ok then error(err, 0) end
  return n
end

local function color3(t) return { t[1], t[2], t[3] } end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function assertColor(got, want, msg)
  assertTrue(got ~= nil, msg .. ": nothing was painted")
  if got.r then got = { got.r, got.g, got.b } end
  local r, g, b = want.r or want[1], want.g or want[2], want.b or want[3]
  assertTrue(near(got[1], r) and near(got[2], g) and near(got[3], b),
    ("%s: got %.3f %.3f %.3f, want %.3f %.3f %.3f"):format(msg, got[1], got[2], got[3], r, g, b))
end

local function band(setId, i) return B.Get(setId).bands[i] end

-- ---------------------------------------------------------------------------
-- The pool
-- ---------------------------------------------------------------------------

test("render: an enabled container gets one pooled instance, watching its unit, drawn at once", function()
  withRenderer(function()
    local id, _, inst = newContainer()
    assertTrue(inst ~= nil, "Sync acquired an instance")
    assertEqual(inst.unit, "target")
    assertTrue(NS.Ticker.IsWatched("target"), "the instance watches its unit")
    assertTrue(inst.frame:IsShown())
    assertEqual(inst.elements.number.text, "20\226\128\14725", "the watch's first read was rendered")
    assertEqual(inst.bandIndex, 3, "(20, 25) by max is MID, 20 to 30")
    assertTrue(Container.Acquire(id) == inst, "Acquire on a live id hands back the same instance")
  end)
end)

test("render: Release returns the frame to the pool cleanly, and the next Acquire reuses it", function()
  withRenderer(function()
    local id, _, inst = newContainer()
    local frame = inst.frame
    inst:Release()
    local free, active = Container.__counts()
    assertEqual(free, 1, "parked")
    assertEqual(active, 0, "nothing left out")
    assertFalse(frame:IsShown(), "hidden")
    assertFalse(NS.Ticker.IsWatched("target"), "its watch went with it")
    assertNil(Container.Get(id))
    assertNil(inst.bandIndex, "no band remembered for the next container it serves")
    local again = Container.Acquire(id)
    assertTrue(again.frame == frame, "the same frame, not a new one")
    assertEqual(again.elements.number.text, "20\226\128\14725", "and it renders from scratch")
  end)
end)

test("render: a deleted or disabled container's instance goes back to the pool on the next apply", function()
  withRenderer(function()
    local a = newContainer()
    local b = CM.Create("target", { bandSet = CM.Get(a).bandSet })
    CM.FlushPending()
    assertTrue(Container.Get(b) ~= nil)
    CM.Get(b).enabled = false
    CM.Delete(a)
    CM.FlushPending()
    assertNil(Container.Get(a), "deleted")
    assertNil(Container.Get(b), "disabled")
    local free, active = Container.__counts()
    assertEqual(free .. "/" .. active, "2/0")
    assertFalse(NS.Ticker.IsWatched("target"))
  end)
end)

test("render: a nameplates container gets no single instance (the plate anchors own those)", function()
  withRenderer(function()
    local id = newContainer({ unit = "nameplates" })
    assertNil(Container.Get(id))
    assertFalse(NS.Ticker.IsWatched("nameplates"), "no watch on a token that is not a unit")
  end)
end)

test("render: the stand-down parks every instance, and the stand-up draws them again", function()
  withRenderer(function()
    local id, _, inst = newContainer()
    NS.SetByPath("enabled", false)
    NS.SyncEnabledHold()
    assertFalse(inst.frame:IsShown(), "nothing drawn while stood down")
    assertNil(Container.Get(id))
    NS.SetByPath("enabled", true)
    NS.SyncEnabledHold()
    CM.FlushPending()
    local back = Container.Get(id)
    assertTrue(back ~= nil and back.frame:IsShown(), "back after the stand-up's apply")
  end)
end)

-- ---------------------------------------------------------------------------
-- Painting only what changed
-- ---------------------------------------------------------------------------

test("render: test_text_set_only_on_change — two identical renders set the text once", function()
  withRenderer(function()
    local _, _, inst = newContainer()
    local fs = inst.elements.number.fs
    local n = count(fs, "SetText", function()
      inst:Render("known", 30, 35)
      inst:Render("known", 30, 35)
    end)
    assertEqual(n, 1, "SetText once for one new string")
    assertEqual(fs:GetText(), "30\226\128\14735")
    n = count(fs, "SetText", function() inst:Render("known", 30, 35) end)
    assertEqual(n, 0, "nothing new, nothing set")
  end)
end)

test("render: test_recolor_only_on_band_change — a new bracket in the same band paints no color", function()
  withRenderer(function()
    local _, setId, inst = newContainer({ elements = { text = { enabled = true } } })
    local num, label = inst.elements.number.fs, inst.elements.text.fs
    local strip = inst.border.strips[1]
    local function spyAll(fn)
      local labels, strips = 0, 0
      local numbers = count(num, "SetTextColor", function()
        labels = count(label, "SetTextColor", function()
          strips = count(strip, "SetColorTexture", fn)
        end)
      end)
      return numbers + labels + strips
    end
    local colors = spyAll(function() inst:Render("known", 25, 28) end)
    assertEqual(colors, 0, "(25, 28) is still MID: no color written")
    assertEqual(inst.elements.number.text, "25\226\128\14728", "but the number moved")
    colors = spyAll(function() inst:Render("known", 30, 35) end)
    assertEqual(inst.bandIndex, 4, "(30, 35) is LONG")
    assertEqual(colors, 3, "the number, the label and the border strip, once each")
    assertColor(color3({ num:GetTextColor() }), band(setId, 4).textColor, "the number wears LONG's text color")
    assertEqual(label:GetText(), "LONG", "the label moves with the band")
  end)
end)

test("render: test_color_modes — band, fixed and class, for the number, the border and the fill", function()
  withRenderer(function()
    local fixed = { r = 0.2, g = 0.4, b = 0.6, a = 1 }
    local _, setId, inst = newContainer({
      frame = { background = { enabled = true, colorMode = "band", bandAlpha = 0.25 } },
      elements = { number = { colorMode = "band" } },
    })
    local mid = band(setId, 3)
    assertColor(color3({ inst.elements.number.fs:GetTextColor() }), mid.textColor, "number by band")
    assertColor(M.__paint(inst.border.strips[1]).color, mid.frameColor, "border by band")
    local fill = M.__paint(inst.background).color
    assertColor(fill, mid.frameColor, "fill by band")
    assertTrue(near(fill[4], 0.25), "the band fill takes bandAlpha")

    local _, _, inst2 = newContainer({
      frame = { border = { colorMode = "fixed", color = fixed },
                background = { enabled = true, colorMode = "fixed", color = { r = 0, g = 0, b = 0, a = 0.5 } } },
      elements = { number = { colorMode = "fixed", color = fixed } },
    })
    assertColor(color3({ inst2.elements.number.fs:GetTextColor() }), fixed, "number fixed")
    assertColor(M.__paint(inst2.border.strips[1]).color, fixed, "border fixed")
    assertTrue(near(M.__paint(inst2.background).color[4], 0.5), "a fixed fill keeps its own alpha")

    local _, _, inst3 = newContainer({
      frame = { border = { colorMode = "class", color = fixed } },
      elements = { number = { colorMode = "class", color = fixed } },
    })
    local mage = M.RAID_CLASS_COLORS.MAGE
    assertColor(color3({ inst3.elements.number.fs:GetTextColor() }), mage, "number in the player's class")
    assertColor(M.__paint(inst3.border.strips[1]).color, mage, "border in the player's class")
  end, "MAGE")
end)

test("render: an unknown range reads the set's gray ? on every element, never a band", function()
  withRenderer(function(_, LRC)
    -- A raise: unknown on both clients (a nil answer on Forever walks the Compat ladder instead).
    LRC.GetRange = function() error("no answer") end
    local _, setId, inst = newContainer({ elements = { text = { enabled = true },
      indicator = { enabled = true, shape = "dot" } } })
    assertEqual(inst.bandIndex, "unknown")
    assertEqual(inst.elements.number.fs:GetText(), "?")
    assertEqual(inst.elements.text.fs:GetText(), "?")
    local gray = B.Get(setId).unknown.color
    assertColor(color3({ inst.elements.number.fs:GetTextColor() }), gray, "number gray")
    assertColor(M.__paint(inst.border.strips[1]).color, gray, "border gray")
    assertColor(M.__paint(inst.elements.indicator.tex).vertex, gray, "indicator gray")
    assertColor(gray, C.HexColor(C.UNKNOWN_COLOR), "the set's gray is the design's #9ca3af")
  end)
end)

test("render: an open-ended bracket reads 40+ and the out-of-range band", function()
  withRenderer(function(_, LRC)
    LRC.GetRange = function() return 40, nil end
    local _, _, inst = newContainer()
    assertEqual(inst.elements.number.fs:GetText(), "40+")
    assertEqual(inst.bandIndex, 5)
  end)
end)

test("render: no unit hides a container that hides with no unit, and shows one that does not", function()
  withRenderer(function()
    M.__unitExists.target = false
    local _, _, inst = newContainer()
    assertFalse(inst.frame:IsShown(), "hideNoUnit (the default)")
    local _, _, inst2 = newContainer({ visibility = { hideNoUnit = false } })
    assertTrue(inst2.frame:IsShown())
    assertEqual(inst2.elements.number.fs:GetText(), "", "no unit, no figure")
  end)
end)

-- ---------------------------------------------------------------------------
-- Elements and layout
-- ---------------------------------------------------------------------------

test("render: test_hidden_elements_not_created — only the enabled elements are built", function()
  withRenderer(function()
    local _, _, inst = newContainer()
    assertTrue(inst.elements.number ~= nil)
    assertNil(inst.elements.text, "the label is off by default")
    assertNil(inst.elements.indicator, "the indicator is off by default")
    assertNil(inst.elements.spells, "the chips are off by default")
  end)
end)

test("render: an element turned off after it was built is hidden and laid out of the row", function()
  withRenderer(function()
    local id, _, inst = newContainer({ elements = { text = { enabled = true } } })
    CM.Get(id).elements.text.enabled = false
    CM.RequestApply()
    CM.FlushPending()
    assertFalse(inst.elements.text.frame:IsShown())
    assertEqual(#inst.layout, 1, "only the number is placed")
  end)
end)

test("render: test_element_order_row_and_column — elements.order, in a row and in a column", function()
  withRenderer(function()
    local id, _, inst = newContainer({ layout = { direction = "row", spacing = 4, padding = 4 },
      elements = { order = { "text", "indicator", "number", "spells" }, text = { enabled = true },
                   indicator = { enabled = true, size = 12 } } })
    local names = {}
    for i, cell in ipairs(inst.layout) do names[i] = cell.name end
    assertEqual(table.concat(names, ","), "text,indicator,number", "the order, enabled ones only")
    local L1, L2, L3 = inst.layout[1], inst.layout[2], inst.layout[3]
    assertEqual(L1.x, 4, "the first cell starts at the padding")
    assertEqual(L2.x, L1.x + L1.w + 4, "each next cell one spacing after the last")
    assertEqual(L3.x, L2.x + L2.w + 4)
    assertTrue(inst.width == L3.x + L3.w + 4, "the row's width closes on the padding")

    CM.Get(id).layout.direction = "column"
    CM.RequestApply()
    CM.FlushPending()
    L1, L2, L3 = inst.layout[1], inst.layout[2], inst.layout[3]
    assertEqual(L1.y, 4)
    assertEqual(L2.y, L1.y + L1.h + 4, "a column stacks downward in order")
    assertEqual(L3.y, L2.y + L2.h + 4)
    assertTrue(inst.height == L3.y + L3.h + 4)
  end)
end)

test("render: the layout's scale and alpha reach the root frame", function()
  withRenderer(function()
    local _, _, inst = newContainer({ layout = { scale = 1.5, alpha = 0.6 } })
    assertTrue(near(inst.frame:GetAlpha(), 0.6))
    assertEqual(inst.appliedScale, 1.5)
  end)
end)

test("render: the indicator shapes draw this addon's textures, recolored by band", function()
  withRenderer(function()
    local id, setId, inst = newContainer({ elements = { indicator = { enabled = true, shape = "diamond" } } })
    local tex = inst.elements.indicator.tex
    assertTrue(tostring(M.__paint(tex).texture):find("media\\textures\\indicators\\diamond", 1, true) ~= nil,
      "the diamond art")
    assertColor(M.__paint(tex).vertex, band(setId, 3).indicatorColor, "MID's indicator color")
    CM.Get(id).elements.indicator.shape = "square"
    CM.RequestApply()
    CM.FlushPending()
    assertTrue(tostring(M.__paint(tex).texture):find("indicators\\square", 1, true) ~= nil, "re-shaped")
  end)
end)

test("render: the bar indicator is LibKa0s-Widgets' data bar, fuller the nearer the band", function()
  withRenderer(function()
    local _, _, inst = newContainer({ elements = { indicator = { enabled = true, shape = "bar" } } })
    local bar = inst.elements.indicator.bar
    assertTrue(bar ~= nil and type(bar.SetValues) == "function", "a W.Bar")
    assertTrue(near(bar.geom.fill, 3 / 5), "MID of five bands is three fifths full")
    inst:Render("known", 0, 5)
    assertTrue(near(bar.geom.fill, 1), "MELEE is full")
    inst:Render("unknown")
    assertTrue(near(bar.geom.fill, 0), "unknown is empty")
  end)
end)

test("render: spell chips are colored by each spell's own answer, and only when it changes", function()
  withRenderer(function()
    local answers = { [100] = true, [200] = false }
    local real = NS.Range.InSpellRange
    NS.Range.InSpellRange = function(id) return answers[id] end
    local ok, err = pcall(function()
      local _, _, inst = newContainer({ elements = { spells = { enabled = true, list = { 100, 200, 300 } } } })
      local chips = inst.elements.spells.chips
      assertEqual(#chips, 3)
      assertColor(M.__paint(chips[1].edge[1]).color, C.HexColor(C.BAND_RAMP[1]), "in range: green")
      assertColor(M.__paint(chips[2].edge[1]).color, C.HexColor(C.BAND_RAMP[5]), "out of range: red")
      assertColor(M.__paint(chips[3].edge[1]).color, C.HexColor(C.UNKNOWN_COLOR), "no answer: gray")
      local n = count(chips[1].edge[1], "SetColorTexture", function()
        inst:Update("known", 25, 28)
      end)
      assertEqual(n, 0, "an unchanged answer paints nothing")
      answers[100] = false
      n = count(chips[1].edge[1], "SetColorTexture", function() inst:Update("known", 25, 28) end)
      assertEqual(n, 1, "a changed answer paints its chip once")
    end)
    NS.Range.InSpellRange = real
    if not ok then error(err, 0) end
  end)
end)

test("render: test_friendly_uses_friendly_set — a friendly unit reads the friendly override", function()
  withRenderer(function()
    local healer = B.Create("Healer", "healer")
    M.UnitIsFriend = function() return true end
    local _, setId, inst = newContainer({ bandSetFriendly = healer })
    inst:Render("known", 35, 40)
    assertEqual(inst.setId, healer, "the friendly set")
    assertEqual(inst.bandIndex, 2, "(35, 40] is the healer's 30 to 40 band")
    M.UnitIsFriend = function() return false end
    inst:Render("known", 35, 40)
    assertEqual(inst.setId, setId, "a hostile unit reads the container's own set")
    assertEqual(inst.bandIndex, 4, "LONG, 30 to 40, of Melee / Ranged")
  end)
end)

test("render: a band set edit repaints every instance on it", function()
  withRenderer(function()
    local _, setId, inst = newContainer()
    B.Get(setId).bands[3].textColor = { r = 0, g = 0, b = 1, a = 1 }
    B.Normalize(setId)
    assertColor(color3({ inst.elements.number.fs:GetTextColor() }), { 0, 0, 1 }, "BANDSETS_CHANGED repainted")
  end)
end)

test("render: RANGE_UPDATED reaches every instance on that unit, and only those", function()
  withRenderer(function()
    M.__unitExists.focus = true
    local _, _, a = newContainer()
    local _, _, b = newContainer()
    local _, _, f = newContainer({ unit = "focus" })
    NS.bus:SendMessage(NS.MSG.RANGE_UPDATED, "target", "known", 30, 35)
    assertEqual(a.elements.number.text, "30\226\128\14735")
    assertEqual(b.elements.number.text, "30\226\128\14735")
    assertEqual(f.elements.number.text, "20\226\128\14725", "focus did not move")
    M.__unitExists.focus = nil
  end)
end)

test("render: every indicator shape ships as a white 64x64 uncompressed 32-bit TGA", function()
  -- An RLE or 24-bit TGA draws nothing and raises nothing in the client (anti-pattern #82), so the
  -- header is the check: image type 2 (uncompressed true-color), 64 x 64, 32 bits, 8 alpha bits.
  for _, shape in ipairs({ "dot", "ring", "square", "diamond", "triangle" }) do
    local path = "media/textures/indicators/" .. shape .. ".tga"
    local fh = io.open(path, "rb")
    assertTrue(fh ~= nil, path .. " is missing")
    local h = fh:read(18)
    fh:close()
    local w = h:byte(13) + h:byte(14) * 256
    local ht = h:byte(15) + h:byte(16) * 256
    assertEqual(h:byte(3), 2, path .. ": uncompressed true-color")
    assertEqual(w .. "x" .. ht, "64x64", path)
    assertEqual(h:byte(17), 32, path .. ": 32 bits per pixel")
    assertEqual(h:byte(18) % 16, 8, path .. ": 8 alpha bits")
  end
end)
