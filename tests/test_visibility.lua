-- tests/test_visibility.lua — the visibility rules (modules/Visibility.lua, NS.Visibility; design spec
-- 5.5): a container's combat rule (any, in, out), its reaction rule (any, hostile, friendly), its "hide
-- with no unit" rule and its out-of-combat opacity, all inside the Master controls' General
-- visibility and Master opacity. The v0.1.0 plan, Task 7.
--
-- The rules are asked through NS.Visibility.Evaluate(container, unit, state) on their own, then
-- through the renderer: a container drawn by the real render path shows and hides on the combat edge
-- (core/RangeMaster.lua's OnCombatChanged) and on the master rows' writes.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile("tests/anchors_env.lua")
local installPaint = dofile("tests/_kit/mock_paint.lua")

--- H.with under the kit's paint recorder (font strings that keep their text, frames their opacity and
--- scale), with the combat edge put back however the case ends.
local function withEnv(body)
  local restore = installPaint(M)
  local ok, err = pcall(H.with, body)
  restore()
  M.InCombatLockdown = function() return false end
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  if not ok then error(err, 0) end
end

local V = NS.Visibility

--- Run `fn(c)` with combat answering `combat`, the target hostile or friendly, on a container table
--- holding `vis`; the combat flag the edge sets is put back however `fn` ends.
local function withWorld(combat, hostile, fn)
  local savedLock, savedAttack, savedFriend = M.InCombatLockdown, M.UnitCanAttack, M.UnitIsFriend
  M.InCombatLockdown = function() return combat end
  M.UnitCanAttack = function() return hostile end
  M.UnitIsFriend = function() return not hostile end
  local ok, err = pcall(fn)
  M.InCombatLockdown, M.UnitCanAttack, M.UnitIsFriend = savedLock, savedAttack, savedFriend
  V.SetCombat(false)
  if not ok then error(err, 0) end
end

local function container(vis)
  return { unit = "target", visibility = vis }
end

-- The expected answer for one cell of the matrix, written out as the spec states the rules.
local function expected(combatRule, reaction, combat, hostile)
  if combatRule == "in" and not combat then return false end
  if combatRule == "out" and combat then return false end
  if reaction == "hostile" and not hostile then return false end
  if reaction == "friendly" and hostile then return false end
  return true
end

test("visibility: test_visibility_matrix — combat any/in/out x reaction any/hostile/friendly x hideNoUnit", function()
  local cells = 0
  for _, combatRule in ipairs({ "any", "in", "out" }) do
    for _, reaction in ipairs({ "any", "hostile", "friendly" }) do
      for _, hideNoUnit in ipairs({ true, false }) do
        for _, combat in ipairs({ true, false }) do
          for _, hostile in ipairs({ true, false }) do
            withWorld(combat, hostile, function()
              local c = container({ combat = combatRule, reaction = reaction, hideNoUnit = hideNoUnit, oocAlpha = 1 })
              local label = ("%s/%s/hide=%s/combat=%s/hostile=%s"):format(combatRule, reaction,
                tostring(hideNoUnit), tostring(combat), tostring(hostile))
              assertEqual(V.Evaluate(c, "target", "known"), expected(combatRule, reaction, combat, hostile),
                label .. " with a unit")
              -- No unit: the combat rule still applies; the reaction rule has nothing to judge, so
              -- hideNoUnit decides.
              local noUnit = expected(combatRule, "any", combat, hostile) and not hideNoUnit
              assertEqual(V.Evaluate(c, "target", "none"), noUnit, label .. " with no unit")
              cells = cells + 1
            end)
          end
        end
      end
    end
  end
  assertEqual(cells, 72, "every cell of the matrix was asked")
end)

test("visibility: with no state given, the unit's existence is asked", function()
  withWorld(false, true, function()
    local saved = M.__unitExists.focus
    M.__unitExists.focus = false
    local c = { unit = "focus", visibility = { combat = "any", reaction = "any", hideNoUnit = true, oocAlpha = 1 } }
    assertFalse(V.Evaluate(c, "focus"), "no focus: hidden")
    M.__unitExists.focus = true
    assertTrue(V.Evaluate(c, "focus"), "a focus: shown")
    M.__unitExists.focus = saved
  end)
end)

test("visibility: an unreadable reaction never passes a hostile or friendly rule", function()
  withWorld(false, true, function()
    M.UnitCanAttack = function() return nil end
    M.UnitIsFriend = function() error("blocked") end
    local c = container({ combat = "any", reaction = "hostile", hideNoUnit = true, oocAlpha = 1 })
    assertFalse(V.Evaluate(c, "target", "known"), "a nil reaction is not hostile")
    c.visibility.reaction = "friendly"
    assertFalse(V.Evaluate(c, "target", "known"), "a raising reaction is not friendly")
  end)
end)

test("visibility: test_ooc_alpha — oocAlpha applies out of combat only, inside the Master opacity", function()
  local saved = NS.db.profile.alpha
  withWorld(false, true, function()
    local c = container({ combat = "any", reaction = "any", hideNoUnit = true, oocAlpha = 0.4 })
    local shown, alpha = V.Evaluate(c, "target", "known")
    assertTrue(shown)
    assertTrue(math.abs(alpha - 0.4) < 1e-9, "out of combat: " .. tostring(alpha))
    M.InCombatLockdown = function() return true end
    alpha = select(2, V.Evaluate(c, "target", "known"))
    assertEqual(alpha, 1, "in combat the out-of-combat opacity does not apply")
    NS.db.profile.alpha = 0.5
    alpha = select(2, V.Evaluate(c, "target", "known"))
    assertTrue(math.abs(alpha - 0.5) < 1e-9, "the Master opacity multiplies: " .. tostring(alpha))
    M.InCombatLockdown = function() return false end
    alpha = select(2, V.Evaluate(c, "target", "known"))
    assertTrue(math.abs(alpha - 0.2) < 1e-9, "both together: " .. tostring(alpha))
    c.visibility.oocAlpha = "junk"
    alpha = select(2, V.Evaluate(c, "target", "known"))
    assertTrue(math.abs(alpha - 0.5) < 1e-9, "a stored value that is no number reads as 1")
  end)
  NS.db.profile.alpha = saved
end)

test("visibility: the General visibility dropdown wraps every container's own rules", function()
  local saved = NS.db.profile.visibility
  withWorld(false, true, function()
    local c = container({ combat = "any", reaction = "any", hideNoUnit = true, oocAlpha = 1 })
    local want = {
      always      = { [false] = true,  [true] = true },
      inCombat    = { [false] = false, [true] = true },
      outOfCombat = { [false] = true,  [true] = false },
      never       = { [false] = false, [true] = false },
    }
    for value, byCombat in pairs(want) do
      NS.db.profile.visibility = value
      for combat, shown in pairs(byCombat) do
        M.InCombatLockdown = function() return combat end
        assertEqual(V.Evaluate(c, "target", "known"), shown, value .. " combat=" .. tostring(combat))
      end
    end
  end)
  NS.db.profile.visibility = saved
end)

test("visibility: the combat edge flag counts as combat before the lockdown answers it", function()
  withWorld(false, true, function()
    local c = container({ combat = "in", reaction = "any", hideNoUnit = true, oocAlpha = 1 })
    assertFalse(V.Evaluate(c, "target", "known"))
    V.SetCombat(true)
    assertTrue(V.Evaluate(c, "target", "known"), "PLAYER_REGEN_DISABLED fires before InCombatLockdown is true")
  end)
end)

-- ---------------------------------------------------------------------------
-- Through the renderer
-- ---------------------------------------------------------------------------

test("visibility: an in-combat container shows on the combat edge and hides on the leave edge", function()
  withEnv(function()
    local _, inst = H.container("target", { visibility = { combat = "in" } })
    assertFalse(inst.frame:IsShown(), "out of combat: hidden")
    M.InCombatLockdown = function() return true end
    NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
    assertTrue(inst.frame:IsShown(), "the combat edge shows it")
    assertEqual(inst.elements.number.fs:GetText(), "20\226\128\14725", "and draws the range it was hiding")
    M.InCombatLockdown = function() return false end
    NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
    assertFalse(inst.frame:IsShown(), "the leave edge hides it")
  end)
end)

test("visibility: a hostile-only container follows the unit's reaction", function()
  withEnv(function()
    local _, inst = H.container("target", { visibility = { reaction = "hostile" } })
    assertFalse(inst.frame:IsShown(), "a friendly target: hidden")
    M.__hostile.target = true
    M.__fireEvent("UNIT_FACTION", "target")
    assertTrue(inst.frame:IsShown(), "turned hostile: shown")
  end)
end)

test("visibility: the frame's opacity is the layout's times oocAlpha out of combat", function()
  withEnv(function()
    local _, inst = H.container("target", { layout = { alpha = 0.8 }, visibility = { oocAlpha = 0.5 } })
    assertTrue(math.abs(inst.frame:GetAlpha() - 0.4) < 1e-9, "out of combat: " .. tostring(inst.frame:GetAlpha()))
    M.InCombatLockdown = function() return true end
    NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
    assertTrue(math.abs(inst.frame:GetAlpha() - 0.8) < 1e-9, "in combat: " .. tostring(inst.frame:GetAlpha()))
    M.InCombatLockdown = function() return false end
    NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  end)
end)

test("visibility: writing General visibility or Master opacity re-evaluates every container", function()
  withEnv(function(p)
    p.visibility, p.alpha = "always", 1
    local _, inst = H.container("target")
    assertTrue(inst.frame:IsShown())
    NS.SetByPath("visibility", "never")
    assertFalse(inst.frame:IsShown(), "never hides it at once")
    NS.SetByPath("visibility", "always")
    assertTrue(inst.frame:IsShown(), "always shows it again")
    NS.SetByPath("alpha", 0.5)
    assertTrue(math.abs(inst.frame:GetAlpha() - 0.5) < 1e-9, "Master opacity: " .. tostring(inst.frame:GetAlpha()))
  end)
end)

test("visibility: Master scale multiplies each container's own scale on the next apply", function()
  withEnv(function(p)
    p.scale = 1
    local id, inst = H.container("target", { layout = { scale = 1.5 } })
    assertEqual(inst.appliedScale, 1.5)
    NS.SetByPath("scale", 2)
    NS.CM.FlushPending()
    assertEqual(NS.Container.Get(id).appliedScale, 3, "the Master scale row asks for an apply")
  end)
end)
