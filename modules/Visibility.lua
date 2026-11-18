local _, NS = ...
-- modules/Visibility.lua — the visibility rules (design spec 5.5): whether a container shows, and at
-- what opacity, from its own rules inside the Master controls' two addon-wide rows.
--
--   NS.Visibility.Evaluate(container, unit, state?) -> shown, alpha
--       shown  the Master controls' General visibility (always, inCombat, outOfCombat, never), then
--              the container's `visibility.combat` (any, in, out), then, with no unit (`state`
--              "none", or UnitExists false when no state is given), `hideNoUnit`; with a unit, its
--              `visibility.reaction` (any, hostile, friendly)
--       alpha  the Master opacity, times `visibility.oocAlpha` out of combat (1 in combat)
--   NS.Visibility.SetCombat(on)    the combat edge (core/RangeMaster.lua's OnCombatChanged)
--   NS.Visibility.InCombat()       the edge's flag, or the client's lockdown
--
-- THE COMBAT FLAG. PLAYER_REGEN_DISABLED is dispatched before InCombatLockdown answers true, so the
-- edge's own flag counts as combat; the lockdown covers a reload inside a fight, which has no edge.
--
-- A REACTION IS READ THROUGH NS.Compat (CanAttack, IsFriend), each guarded: an answer the client will
-- not give (nil, a raise, a secret) passes neither the hostile nor the friendly rule, the side that
-- shows nothing it cannot vouch for. With no unit there is no reaction to judge, so `hideNoUnit`
-- decides alone.
--
-- WHO ASKS. The renderer (modules/Container.lua) on every render of a shown-or-hidden instance, and
-- again over every instance on the combat edge and on a write of the General visibility or Master
-- opacity rows (NS.Container.RefreshVisibility). Test mode and Sim mode show every container whatever
-- these say: the renderer does not ask while a preview runs.

NS.Visibility = NS.Visibility or {}
local Visibility = NS.Visibility

local inCombat = false

function Visibility.SetCombat(on)
    inCombat = on and true or false
end

function Visibility.InCombat()
    return inCombat or (InCombatLockdown() and true or false)
end

--- The Master controls' General visibility row (options-ui-§15's four values).
local function masterAllows(combat)
    local m = NS.GetSetting("visibility")
    if m == "never" then return false end
    if m == "inCombat" then return combat end
    if m == "outOfCombat" then return not combat end
    return true
end

local function combatAllows(rule, combat)
    if rule == "in" then return combat end
    if rule == "out" then return not combat end
    return true
end

local function reactionAllows(rule, unit)
    if rule == "hostile" then return NS.Compat.CanAttack(unit) == true end
    if rule == "friendly" then return NS.Compat.IsFriend(unit) == true end
    return true
end

local function exists(unit, state)
    if state ~= nil then return state ~= "none" end
    return type(unit) == "string" and UnitExists(unit) == true
end

--- A stored opacity as a number in [0, 1]; anything else reads as 1.
local function unit01(v)
    v = tonumber(v)
    if not v then return 1 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function alphaFor(vis, combat)
    local a = unit01(NS.GetSetting("alpha"))
    if not combat then a = a * unit01(vis.oocAlpha) end
    return a
end

--- Whether container `c` shows for `unit` (its range `state` when the caller has it), and at what
--- opacity. See the file header for the order the rules are asked in.
--- @return boolean shown, number alpha
function Visibility.Evaluate(c, unit, state)
    local vis = type(c) == "table" and type(c.visibility) == "table" and c.visibility or {}
    local combat = Visibility.InCombat()
    local alpha = alphaFor(vis, combat)
    if not masterAllows(combat) or not combatAllows(vis.combat, combat) then return false, alpha end
    if not exists(unit, state) then return not vis.hideNoUnit, alpha end
    return reactionAllows(vis.reaction, unit), alpha
end
