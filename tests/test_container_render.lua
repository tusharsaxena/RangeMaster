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

-- ---------------------------------------------------------------------------
-- The unit behind the token changed (review fixes)
-- ---------------------------------------------------------------------------

--- Run `fn` with NS.Range.InSpellRange answering from `answers` (keyed by spell id), then restore.
local function withSpellAnswers(answers, fn)
  local real = NS.Range.InSpellRange
  NS.Range.InSpellRange = function(id) return answers[id] end
  local ok, err = pcall(fn)
  NS.Range.InSpellRange = real
  if not ok then error(err, 0) end
end

test("render: the bar indicator repaints its fill in each new band's indicator color", function()
  -- red under: one color table reused across paints; W.Bar's SetValues repaints only on a new table.
  withRenderer(function()
    local _, setId, inst = newContainer({ elements = { indicator = { enabled = true, shape = "bar" } } })
    local bar = inst.elements.indicator.bar
    local function fillColor()
      local p = M.__paint(bar.fill)
      return p.color or p.vertex   -- a flat fill (no bar texture) is SetColorTexture's, vertex white
    end
    assertColor(fillColor(), band(setId, 3).indicatorColor, "MID's indicator color")
    inst:Render("known", 0, 5)
    assertColor(fillColor(), band(setId, 1).indicatorColor, "MELEE's, after the band moved")
    inst:Render("known", 40, nil)
    assertColor(fillColor(), band(setId, 5).indicatorColor, "OOR's, after it moved again")
  end)
end)

test("render: a target swap at the same bracket re-resolves the band set through the event path", function()
  -- red under: PLAYER_TARGET_CHANGED reaching only Ticker.Refresh, which sends nothing for a bracket
  -- that did not move, so the hostile set's band, label and colors stay on a friendly target.
  withRenderer(function()
    local healer = B.Create("Healer", "healer")
    M.UnitIsFriend = function() return false end
    local _, setId, inst = newContainer({ bandSetFriendly = healer, elements = { text = { enabled = true } } })
    assertEqual(inst.setId, setId, "a hostile target reads the container's own set")
    assertEqual(inst.elements.text.fs:GetText(), "MID")
    M.UnitIsFriend = function() return true end
    M.__fireEvent("PLAYER_TARGET_CHANGED")
    assertEqual(inst.setId, healer, "the friendly target, at the same (20, 25), reads the friendly set")
    assertEqual(inst.bandIndex, 1, "(20, 25) is the healer's 0 to 30 band")
    assertColor(color3({ inst.elements.number.fs:GetTextColor() }), band(healer, 1).textColor,
      "and wears its color")
  end)
end)

test("render: a reaction change on the same unit (UNIT_FACTION) re-resolves the band set", function()
  withRenderer(function()
    local healer = B.Create("Healer", "healer")
    M.UnitIsFriend = function() return true end
    local _, setId, inst = newContainer({ bandSetFriendly = healer })
    assertEqual(inst.setId, healer)
    M.UnitIsFriend = function() return false end
    M.__fireEvent("UNIT_FACTION", "target")
    assertEqual(inst.setId, setId, "the unit turned hostile: the container's own set")
    M.UnitIsFriend = function() return true end
    M.__fireEvent("UNIT_FACTION", "party1")
    assertEqual(inst.setId, setId, "another unit's faction change reaches no container on target")
  end)
end)

test("render: a target swap at the same bracket asks every spell chip again", function()
  withRenderer(function()
    local answers = { [100] = true }
    withSpellAnswers(answers, function()
      local _, _, inst = newContainer({ elements = { spells = { enabled = true, list = { 100 } } } })
      local chip = inst.elements.spells.chips[1]
      assertEqual(chip.result, true)
      answers[100] = false
      M.__fireEvent("PLAYER_TARGET_CHANGED")
      assertEqual(chip.result, false, "the new target's answer")
      assertColor(M.__paint(chip.edge[1]).color, C.HexColor(C.BAND_RAMP[5]), "painted red")
    end)
  end)
end)

test("render: a spell chip's answer moving inside one bracket is drawn on the next tick", function()
  -- A 30 yd spell's edge falls inside LibRangeCheck's 28 to 35 bracket: the triple never moves, so
  -- RANGE_UPDATED never goes out, and the chip is asked on the tick's steady read instead.
  withRenderer(function()
    local answers = { [100] = true }
    withSpellAnswers(answers, function()
      local _, _, inst = newContainer({ elements = { spells = { enabled = true, list = { 100 } } } })
      local chip = inst.elements.spells.chips[1]
      local num = inst.elements.number.fs
      answers[100] = false
      local sets = count(num, "SetText", function() NS.Ticker.__handle().fn() end)
      assertEqual(chip.result, false, "the tick asked the chip again")
      assertEqual(sets, 0, "and the figure, which did not move, was not set")
      local paints = count(chip.edge[1], "SetColorTexture", function() NS.Ticker.__handle().fn() end)
      assertEqual(paints, 0, "an unchanged answer on the next tick paints nothing")
    end)
  end)
end)

test("render: colorMode class reads the TRACKED unit's class, and follows a target swap", function()
  -- options-ui-§17: a range container describes its unit, so class is the unit's, not the player's.
  withRenderer(function()
    local classOf = { player = "MAGE", target = "WARRIOR" }
    local realClass = M.UnitClass
    M.UnitClass = function(unit) local t = classOf[unit or "player"]; return t, t end
    local ok, err = pcall(function()
      local fixed = { r = 0.2, g = 0.4, b = 0.6, a = 1 }
      local _, _, inst = newContainer({ frame = { border = { colorMode = "class", color = fixed } },
        elements = { number = { colorMode = "class", color = fixed } } })
      local fs = inst.elements.number.fs
      assertColor(color3({ fs:GetTextColor() }), M.RAID_CLASS_COLORS.WARRIOR, "the target's class")
      assertColor(M.__paint(inst.border.strips[1]).color, M.RAID_CLASS_COLORS.WARRIOR, "border too")
      classOf.target = "PRIEST"
      M.__fireEvent("PLAYER_TARGET_CHANGED")
      assertColor(color3({ fs:GetTextColor() }), M.RAID_CLASS_COLORS.PRIEST, "the new target's class")
      classOf.target = nil
      M.__fireEvent("PLAYER_TARGET_CHANGED")
      assertColor(color3({ fs:GetTextColor() }), fixed, "an unresolvable class falls through to the swatch")
    end)
    M.UnitClass = realClass
    if not ok then error(err, 0) end
  end, "MAGE")
end)

test("render: a skin change in combat re-applies nothing until combat ends", function()
  -- red under: OnLooksChanged calling Container.Sync directly, which places frames mid-combat.
  withRenderer(function()
    local _, _, inst = newContainer()
    local realLock = M.InCombatLockdown
    M.InCombatLockdown = function() return true end
    local ok, err = pcall(function()
      local placed = count(inst.frame, "SetPoint", function()
        M.LibStub("LibKa0s-Skin-1.0"):__NotifyLooks("RangeMaster")
        CM.FlushPending()
      end)
      assertEqual(placed, 0, "nothing placed while in combat")
      assertTrue(CM.__pending(), "the re-apply is owed")
      M.InCombatLockdown = realLock
      placed = count(inst.frame, "SetPoint", function() CM.FlushPending("regen") end)
      assertTrue(placed > 0, "the leave edge runs the held re-apply")
    end)
    M.InCombatLockdown = realLock
    if not ok then error(err, 0) end
  end)
end)

--- Run `fn` with NS.GetLSM answering a fake LibSharedMedia that knows one font and one border.
local FAKE_FONT, FAKE_EDGE = "Interface\\AddOns\\Fake\\Fancy.ttf", "Interface\\AddOns\\Fake\\Edge"
local function withFakeLSM(fn)
  local real = NS.GetLSM
  local lsm = { Fetch = function(_, kind, key)
    if kind == "font" and key == "Fancy" then return FAKE_FONT end
    if kind == "border" and key == "Edge" then return FAKE_EDGE end
    if kind == "border" and key == "Solid" then return "Interface\\Buttons\\WHITE8X8" end
  end }
  NS.GetLSM = function() return lsm end
  local ok, err = pcall(fn)
  NS.GetLSM = real
  if not ok then error(err, 0) end
end

test("render: an element font naming a LibSharedMedia key draws that face at the stored size", function()
  withRenderer(function()
    withFakeLSM(function()
      local _, _, inst = newContainer({ elements = { number = { font = "Fancy", size = 17 } } })
      local font = M.__paint(inst.elements.number.fs).font
      assertEqual(font[1], FAKE_FONT, "LSM's path for the key")
      assertEqual(font[2], 17, "at the stored size")
      local _, _, inst2 = newContainer({ elements = { number = { font = "Unknown" } } })
      assertEqual(M.__paint(inst2.elements.number.fs).font[1], C.FALLBACK_FONT,
        "a key LSM does not know draws the fallback face")
    end)
  end)
end)

test("render: an element's shadow turns the font string's shadow offset on and off", function()
  withRenderer(function()
    local id, _, inst = newContainer({ elements = { number = { shadow = true }, text = { enabled = true } } })
    local offset = M.__paint(inst.elements.number.fs).shadowOffset
    assertEqual(offset[1], 1, "shadow on: offset one right")
    assertEqual(offset[2], -1, "and one down")
    offset = M.__paint(inst.elements.text.fs).shadowOffset
    assertEqual(offset[1], 0, "the text element's shadow is its own, off")
    assertEqual(offset[2], 0)
    CM.SetField(id, "elements.number.shadow", false)
    CM.FlushPending()
    offset = M.__paint(inst.elements.number.fs).shadowOffset
    assertEqual(offset[1], 0, "shadow off: no offset")
    assertEqual(offset[2], 0)
  end)
end)

test("render: a LibSharedMedia border draws on a backdrop of its own, band-colored, its tiling tracked", function()
  withRenderer(function()
    local resized = 0
    local realMixin, realMixinFn = M.BackdropTemplateMixin, M.Mixin
    M.BackdropTemplateMixin = { OnBackdropSizeChanged = function() resized = resized + 1 end }
    M.Mixin = function(o, m) for k, v in pairs(m) do o[k] = v end return o end
    local ok, err = pcall(withFakeLSM, function()
      local _, setId, inst = newContainer({ frame = { border = { enabled = true, texture = "Edge", size = 8 } } })
      local host = inst.border.backdrop
      assertTrue(host ~= nil and host:IsShown(), "the media border's host is shown")
      assertEqual(host:GetBackdrop().edgeFile, FAKE_EDGE)
      assertEqual(host:GetBackdrop().edgeSize, 8)
      assertFalse(inst.border.strips[1]:IsShown(), "the Solid strips are down")
      assertColor({ host:GetBackdropBorderColor() }, band(setId, 3).frameColor, "the band's frame color")
      local onSize = host:GetScript("OnSizeChanged")
      assertTrue(onSize ~= nil, "the host re-tiles its edge when its size moves, as the template does")
      onSize(host, 10, 10)
      assertEqual(resized, 1, "through the mixin's own OnBackdropSizeChanged")
      local _, _, solid = newContainer({ frame = { border = { enabled = true, texture = "Solid", size = 2 } } })
      assertTrue(solid.border.strips[1]:IsShown(), "Solid draws the strips")
      assertNil(solid.border.backdrop, "and builds no backdrop")
    end)
    M.BackdropTemplateMixin, M.Mixin = realMixin, realMixinFn
    if not ok then error(err, 0) end
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

-- ---------------------------------------------------------------------------
-- The first draw
-- ---------------------------------------------------------------------------

test("render: a stored container draws at login, whatever the skin settings are", function()
  -- red under: OnEnable's NS.CM.RequestApply() removed (the first draw rides on the skin's callback,
  -- which a default skin with "Ignore settings panel" unticked never fires).
  withRenderer(function(p)
    p.skin = p.skin or {}
    p.skin.ignorePanel = false
    local id = newContainer()
    Container.__reset()
    CM.__reset()
    assertNil(Container.Get(id), "the pool starts empty, as after a /reload")
    local savedPreset, savedSkin = NS.MaybeShowPresetPicker, NS.MaybeShowSkinPicker
    NS.MaybeShowPresetPicker, NS.MaybeShowSkinPicker = function() end, function() end
    local ok, err = pcall(function()
      NS.addon:OnEnable()
      M.__fireTimers()
    end)
    NS.MaybeShowPresetPicker, NS.MaybeShowSkinPicker = savedPreset, savedSkin
    if not ok then error(err, 0) end
    assertTrue(Container.Get(id) ~= nil, "the stored container drew on the login's own apply")
  end)
end)

test("render: a container with no stored chip list draws the logged-in character's class chips", function()
  -- red under: a renderer that reads elements.spells.list alone (an empty stored list draws nothing).
  withRenderer(function()
    newContainer({ elements = { spells = { enabled = true } } })   -- made by a mage
    M.__context.classToken = "PRIEST"                                -- a priest logs in on the profile
    Container.__reset()
    CM.RequestApply()
    CM.FlushPending()
    local inst = Container.Get(CM.List()[1])
    local seeds = NS.SpellSeeds[NS.Compat.ClientKey()].PRIEST.chips
    assertEqual(#inst.elements.spells.chips, #seeds, "the priest's chips are drawn")
    local asked = {}
    local real = NS.Range.InSpellRange
    NS.Range.InSpellRange = function(id) asked[#asked + 1] = id; return true end
    local ok, err = pcall(function() inst:Update("known", 20, 25) end)
    NS.Range.InSpellRange = real
    if not ok then error(err, 0) end
    assertEqual(asked[1], seeds[1], "and the priest's spells are the ones asked")
  end, "MAGE")
end)
