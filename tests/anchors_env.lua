-- tests/anchors_env.lua — the shared harness of the four anchor suites (tests/test_anchors_*.lua):
-- a fresh profile, the renderer and the anchors reset, the unit and plate stand-ins, and spies.
-- Not a suite: each anchor suite loads it with dofile.
--
-- Every case runs on a FRESH profile with the renderer's pools, the plate registry and the anchor
-- sets dropped before and after, so one case's instances, plates and follow never leak into the
-- next. What it swaps (the combat answer, the hostility answer, the unit set, the plates, the
-- cursor, LibRangeCheck's GetRange, the lock, NS.Debug) is put back however the case ends.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks

local H = {}

local UNITS = { "target", "focus", "pet", "mouseover" }

--- Run `body(p)` on a fresh profile with target present at (20, 25) and no plate anywhere.
function H.with(body)
  local CM, Container = NS.CM, NS.Container
  local LRC = M.LibStub("LibRangeCheck-3.0", true)
  local saved = {
    db = NS.db, combat = M.InCombatLockdown, attack = M.UnitCanAttack, get = LRC.GetRange,
    debug = NS.Debug, locked = NS.db.profile.locked, exists = {},
  }
  for _, u in ipairs(UNITS) do saved.exists[u] = M.__unitExists[u] end
  NS.db = { profile = { locked = true }, global = saved.db.global }
  CM.__reset()
  Container.__reset()
  NS.Plates.__reset()
  NS.Anchors.__reset()
  for k in pairs(M.__plates) do M.__plates[k] = nil end
  M.__hostile = {}
  M.UnitCanAttack = function(_, unit) return M.__hostile[unit] == true end
  M.InCombatLockdown = function() return false end
  LRC.GetRange = function() return 20, 25 end
  M.__unitExists.target = true
  M.__cursor[1], M.__cursor[2] = 0, 0
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(NS.db.profile)
    body(NS.db.profile)
  end)
  Container.__reset()
  NS.Anchors.__reset()
  NS.Plates.__reset()
  CM.__reset()
  for k in pairs(M.__plates) do
    M.__unitExists[k] = nil
    M.__plates[k] = nil
  end
  NS.db = saved.db
  M.InCombatLockdown, M.UnitCanAttack, LRC.GetRange, NS.Debug =
    saved.combat, saved.attack, saved.get, saved.debug
  for _, u in ipairs(UNITS) do M.__unitExists[u] = saved.exists[u] end
  if not ok then error(err, 0) end
end

--- A container on `unit` with `opts`, applied now (the next frame's flush run here).
function H.container(unit, opts)
  local id = NS.CM.Create(unit, opts)
  NS.CM.FlushPending()
  return id, NS.Container.Get(id)
end

--- A frame-shaped stand-in that answers IsForbidden plainly (the kit's stub answers every
--- capitalized method with the frame itself, which reads as truthy) and its own global name.
function H.frame(name, forbiddenFlag)
  local f = M.CreateFrame("Frame", name)
  rawset(f, "IsForbidden", function() return forbiddenFlag == true end)
  if name then rawset(f, "GetName", function() return name end) end
  return f
end

--- A nameplate for `token`, shown: it resolves through C_NamePlate and its unit exists.
function H.plate(token, hostile, forbiddenFlag)
  local p = H.frame(nil, forbiddenFlag)
  p.namePlateUnitToken = token
  M.__plates[token] = p
  M.__unitExists[token] = true
  M.__hostile[token] = hostile and true or nil
  return p
end

--- NAME_PLATE_UNIT_ADDED for `token`, through the addon's own registration.
function H.added(token) M.__fireEvent("NAME_PLATE_UNIT_ADDED", token) end

--- NAME_PLATE_UNIT_REMOVED for `token`, fired while the client still resolves the token (as it does
--- while the event dispatches), then the plate gone.
function H.removed(token)
  M.__fireEvent("NAME_PLATE_UNIT_REMOVED", token)
  M.__plates[token] = nil
  M.__unitExists[token] = nil
end

--- Every SetPoint `frame` receives while `fn` runs, as { point, relativeTo, relPoint, x, y }.
function H.points(frame, fn)
  local calls = {}
  rawset(frame, "SetPoint", function(_, ...) calls[#calls + 1] = { ... } end)
  local ok, err = pcall(fn)
  rawset(frame, "SetPoint", nil)
  if not ok then error(err, 0) end
  return calls
end

--- Capture NS.Debug lines while `fn` runs (the sink stays quiet); answers them as "[tag] text".
function H.debugLines(fn)
  local lines, real = {}, NS.Debug
  NS.Debug = function(tag, fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    lines[#lines + 1] = "[" .. tostring(tag) .. "] " .. (ok and text or tostring(fmt))
  end
  local ok, err = pcall(fn)
  NS.Debug = real
  if not ok then error(err, 0) end
  return lines
end

--- The addon's frames that carry an OnUpdate script right now (LibRangeCheck's own left out).
function H.onUpdates()
  local LRC = M.LibStub("LibRangeCheck-3.0", true)
  local out = {}
  for _, t in ipairs(M.__timers()) do
    if type(t) == "table" and t.__scripts and t.__scripts.OnUpdate and t ~= (LRC and LRC.frame) then
      out[#out + 1] = t
    end
  end
  return out
end

return H
