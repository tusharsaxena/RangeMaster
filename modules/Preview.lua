local _, NS = ...
-- modules/Preview.lua — what Test mode draws (design spec 5.5, preview-mode), and the one place that
-- decides which preview the range displays show.
--
--   NS.Preview.SetTestMode(on, why?) -> boolean   Test mode through its one writer, NS.SetTestMode
--                                       (core/RangeMaster.lua); false when a start was refused
--   NS.Preview.Kind() -> "sim"|"test"|nil          the preview drawing now: a running sweep wins
--   NS.Preview.Refresh()                 draw what Kind says: NS.Range's source, the renderer's
--                                       preview (NS.Container.SetPreview) and a ticker pass
--   NS.Preview.PLACEHOLDER               the placeholder triple, { "known", 20, 25 }
--
-- TEST MODE draws one placeholder on every enabled container through the real render path: the
-- range engine answers the placeholder for every token (NS.Range.SetSource), the ticker reads and
-- sends it like a live range, and the renderer shows each container whatever its visibility says,
-- a `nameplates` container through a stand-in and a container whose frame or plate is missing at its
-- screen point, each with the amber TestStrip. Every spell chip reads in range; a band rule gets no
-- answer, so a rule band reads its fallback yards and the placeholder lands where it always did.
--
-- ONE OWNER OF THE SOURCE. Both modes reach the renderer through Refresh, never on their own: this
-- file listens for MODE_CHANGED, and modules/Sim.lua calls Refresh when its session starts and stops.
-- So the two can never leave a stale source behind, and Sim mode, while its session runs, wins over
-- Test mode (which core/RangeMaster.lua also refuses to start beside a running sim).
--
-- Session state only: nothing here is stored, and nothing runs in combat (both modes are refused in
-- it and ended by it, while secure writes are still allowed).

NS.Preview = NS.Preview or {}
local Preview = NS.Preview

Preview.PLACEHOLDER = { "known", 20, 25 }

local PH = Preview.PLACEHOLDER
local placeholder = {
    Get = function() return PH[1], PH[2], PH[3] end,
    InSpell = function() return true end,
    InRole = function() return nil end,
}

local current = nil   -- the source set now, or nil (live)
local drawnKind = nil

function Preview.SetTestMode(on, why)
    return NS.SetTestMode(on, why or "preview")
end

function Preview.Kind()
    if NS.Sim and NS.Sim.IsRunning and NS.Sim.IsRunning() then return "sim" end
    if NS.IsTestMode() then return "test" end
    return nil
end

local function sourceFor(kind)
    if kind == "sim" then return NS.Sim.Source end
    if kind == "test" then return placeholder end
    return nil
end

--- Draw the preview Kind() names, if it is not the one drawn already.
function Preview.Refresh()
    local kind = Preview.Kind()
    if kind == drawnKind then return end
    drawnKind = kind
    current = sourceFor(kind)
    NS.Range.SetSource(current)
    NS.Container.SetPreview(kind)
    NS.Ticker.Refresh()
    NS.Debug("Mode", "drawing %s", kind or "live ranges")
end

-- Suite seam: the preview drawn now.
function Preview.__drawn() return drawnKind end

local target = NS.NewBusTarget()
if target then
    target:RegisterMessage(NS.MSG.MODE_CHANGED, function() Preview.Refresh() end)
end
