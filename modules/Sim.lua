local addonName, NS = ...
-- modules/Sim.lua — Sim mode (design spec 5.5): a simulated unit walks 0 to 50 to 0 yd over 20 s, on
-- LibKa0s-Sim-1.0's session, timeline and step panel, through every container's real render path.
--
--   NS.Sim.SetSimMode(on, why?) -> boolean   Sim mode through its one writer, NS.SetSimMode
--                                       (core/RangeMaster.lua); false when a start was refused
--   NS.Sim.IsRunning() -> boolean        a sweep session runs
--   NS.Sim.Source                        the fake range the sweep answers (modules/Preview.lua sets it)
--   NS.Sim.RunVerb(rest)                 `/rm sim <verb>`: the library's own verbs, printed in chat
--   NS.Sim.Session(), NS.Sim.Seam()      the LibKa0s-Sim instance and its seam (nil without the library)
--   NS.Sim.TOP, STEP_YD, STEP_DELAY      50 yd, 5 yd a step, 1 s a step
--
-- THE WORLD is one number, the simulated distance. Each timeline step sets it and asks the ticker for
-- a pass (NS.Ticker.Refresh), so every container hears RANGE_UPDATED and renders through the live
-- path: band changes repaint, and band sounds settle and play (modules/Sounds.lua). The range is the
-- bracket one yard either side of the distance, `50+` at the far end, and a spell chip reads in range
-- while the distance is inside the spell's own range (NS.Compat.GetSpellInfo). A band rule reads in
-- range while the distance is inside its anchor's range as the client reported it at the last
-- rebuild (NS.Range.Anchor: Hawk Eye's 41 yd, not the 35 stored); an anchor with no reported max
-- range gives no answer, and the band reads its yards (dynamic-bands plan D3). Nothing is read from
-- the client for it, so the seam wraps nothing (an empty compat table, as AbsorbTracker's), and
-- nothing is stored: the panel's position is session-only and no setting is written.
--
-- THE MODE AND THE SESSION ARE ONE. Sim mode on (the Master controls box, the launcher, `/rm sim`)
-- starts the sweep and runs it; the session ending, however it ends (its last step, `/rm sim stop`,
-- the panel's Stop, combat, a stand-down, Sim mode off), turns the mode off and puts the live range
-- back. A session a typed `/rm sim start sweep` began turns the mode on. The step panel shows for the
-- whole session (preview-mode: it is the session's mark) and every container carries the cyan strip.
--
-- THE PANEL IS PINNED while the session runs: no window strip marks this addon's session, so the
-- panel may not be closed by a click (preview-mode, *The in-game simulator*: `close = false`). The
-- vendored LibKa0s-Sim-1.0 takes no `close` on its panel descriptor (descriptor.panel raises on one)
-- and lists the frame on UISpecialFrames when it builds it, so the pin is composed, as KickCD's is:
-- the frame, reached by its documented name `<name>SimPanel`, has its close mark hidden and comes
-- off UISpecialFrames (Escape leaves it); the stop puts both back. Its Stop row, `/rm sim stop`,
-- combat and Sim mode off still end the session.
--
-- LINES. The library's lines go to the debug console (tag `Sim`), so a running sweep does not print
-- a line a step into chat; a typed `/rm sim <verb>` prints its answer in chat.

NS.Sim = NS.Sim or {}
local Sim = NS.Sim
local L = NS.L

Sim.TOP, Sim.STEP_YD, Sim.STEP_DELAY = 50, 5, 1

local Lib = LibStub and LibStub("LibKa0s-Sim-1.0", true)
local session, seam
local distance = 0
local chatty = false

-- ---------------------------------------------------------------------------
-- The fake range
-- ---------------------------------------------------------------------------

local function bracket()
    if distance >= Sim.TOP then return "known", Sim.TOP, nil end
    return "known", math.max(0, distance - 1), distance + 1
end

local function inSpell(id)
    local C = NS.Compat
    local name, _, _, minRange, maxRange = C.GetSpellInfo(id)
    if not name or C.IsSecret(minRange) or C.IsSecret(maxRange) or type(maxRange) ~= "number" then return nil end
    return distance >= (tonumber(minRange) or 0) and distance <= maxRange
end

--- A band rule's answer: the distance inside the anchor's reported range, or nil with no max.
local function inRole(anchor)
    local maxRange = anchor and anchor.maxRange
    if type(maxRange) ~= "number" then return nil end
    return distance >= (tonumber(anchor.minRange) or 0) and distance <= maxRange
end

Sim.Source = {
    Get = function() return bracket() end,
    InSpell = function(id) return inSpell(id) end,
    InRole = function(_, _, anchor) return inRole(anchor) end,
}

-- ---------------------------------------------------------------------------
-- The scenario
-- ---------------------------------------------------------------------------

local function distanceStep(yd)
    return { kind = "distance", yd = yd, label = L["Target at %d yd"]:format(yd) }
end

--- 0, 5, ... 50, 45, ... 0 yd, then the step that ends the session. Fresh tables each call: the
--- library previews the timeline while idle.
local function timeline()
    local steps = {}
    for yd = 0, Sim.TOP, Sim.STEP_YD do steps[#steps + 1] = distanceStep(yd) end
    for yd = Sim.TOP - Sim.STEP_YD, 0, -Sim.STEP_YD do steps[#steps + 1] = distanceStep(yd) end
    steps[#steps + 1] = { kind = "end", label = L["Sweep complete"] }
    return steps
end

local SCENARIOS = {
    names = { "sweep" },
    defs = { sweep = { label = L["A target walking out to 50 yd and back"], timeline = timeline } },
}

local function play(step)
    if step.kind == "end" then
        session:Stop("finished")
        return step.label
    end
    distance = step.yd
    NS.Ticker.Refresh()
    return step.label
end

local PANEL_NAME = addonName .. "SimPanel"

--- Pin the step panel (`on`) or unpin it: its close mark hidden or shown, its name off or back on
--- UISpecialFrames. Idempotent; a frame not built yet is left alone. Answers whether it found one.
local function pinPanel(on)
    local frame = _G[PANEL_NAME]
    if type(frame) ~= "table" then return false end
    local close = frame.closeButton
    if type(close) == "table" and close.SetShown then close:SetShown(not on) end
    local special = UISpecialFrames
    if type(special) ~= "table" then return true end
    local at
    for i = #special, 1, -1 do
        if special[i] == PANEL_NAME then at = i end
    end
    if on and at then table.remove(special, at) end
    if not on and not at then special[#special + 1] = PANEL_NAME end
    return true
end

local function prepare(_, _, _, ready)
    distance = 0
    NS.Preview.Refresh()
    if session:ShowPanel() then pinPanel(true) end
    ready()
end

--- Why a sweep may not start now, or nil. Read inside the seam's Live.
local function refusal()
    if InCombatLockdown() then return L["Cannot start a preview mode during combat."] end
    return nil
end

-- ---------------------------------------------------------------------------
-- The mode
-- ---------------------------------------------------------------------------

--- MODE_CHANGED's `why` as the session's stop reason (H6: a stand-down stops it as "standDown").
local STOP_REASON = { ["combat started"] = "combat", ["stood down"] = "standDown" }

function Sim.SetSimMode(on, why)
    return NS.SetSimMode(on, why or "sim")
end

function Sim.IsRunning()
    return session ~= nil and session:IsActive() == true
end

function Sim.Session() return session end
function Sim.Seam() return seam end

local function start()
    if not session then
        NS.Printf("|cff808080%s|r", L["Sim mode needs LibKa0s-Sim-1.0, which did not load."])
        return NS.SetSimMode(false, "no simulator")
    end
    if session:IsActive() then return end
    if not session:Start({ scenario = "sweep" }) then return NS.SetSimMode(false, "sim refused") end
    session:Run()
end

local function onModeChanged(_, mode, on, why)
    if mode ~= "sim" then return end
    if on then return start() end
    if Sim.IsRunning() then session:Stop(STOP_REASON[why] or "mode") end
end

function Sim.RunVerb(rest)
    if not session then
        NS.Printf("|cff808080%s|r", L["Sim mode needs LibKa0s-Sim-1.0, which did not load."])
        return false
    end
    chatty = true
    local ok, res = pcall(session.RunVerb, session, rest or "")
    chatty = false
    if not ok then error(res, 0) end
    return res
end

local function say(line)
    if chatty then return NS.Print(line) end
    NS.Debug("Sim", "%s", tostring(line))
end

if Lib then
    seam = Lib:NewSeam({}, {
        name = addonName,
        debug = function(tag, fmt, ...) NS.Debug(tag, fmt, ...) end,
    })
    session = Lib:New({
        name = addonName,
        seam = seam,
        slash = "/rm sim",
        deliver = function() return 0 end,
        isStoodDown = function() return NS.IsStoodDown() end,
        scenarios = SCENARIOS,
        prepare = prepare,
        play = play,
        refusal = refusal,
        stepDelay = function() return Sim.STEP_DELAY end,
        stopText = {
            finished = L["Simulation finished."],
            mode = L["Simulation stopped: Sim mode is off."],
            combat = L["Simulation stopped: combat started."],
        },
        print = say,
        debug = function(_, fmt, ...) NS.Debug("Sim", fmt, ...) end,
        panel = {
            title = function() return L["Range Master - SIM"] end,
            check = NS.Icon("confirm"),
        },
    })
    -- A session a typed verb began is Sim mode too (the mode's writer refuses what the session would).
    session:AddListener(function(s)
        if s:IsActive() and not NS.IsSimMode() then NS.SetSimMode(true, "sim session") end
    end)
    -- However it ended: the live range back, the panel away, the mode off.
    session:OnStop(function(_, reason)
        distance = 0
        NS.Preview.Refresh()
        session:HidePanel()
        pinPanel(false)
        NS.SetSimMode(false, "sim " .. tostring(reason))
    end)
end

local target = NS.NewBusTarget()
if target then target:RegisterMessage(NS.MSG.MODE_CHANGED, onModeChanged) end
