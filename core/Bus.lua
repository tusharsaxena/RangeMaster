local addonName, NS = ...
-- core/Bus.lua — the closed cross-module message bus (architecture-§4), and this addon's seam onto
-- LibKa0s-Bus-1.0 (libs/LibKa0s/Bus.lua; contract in LibKa0s docs/api/Bus/version-1-docs.md).
--
-- Modules never reach into each other's tables to trigger work: a producer PUBLISHES a named message
-- on NS.bus, and every receiver SUBSCRIBES on its OWN target from NS.NewBusTarget(), never two
-- receivers on one target (anti-pattern #32). CallbackHandler keys callbacks by (message, target), so
-- a second RegisterMessage on a shared object would silently overwrite the first.
--
-- The catalog at the bottom is the contract: one sender per message. docs/ARCHITECTURE.md → Message Bus lists each
-- one's sender, payload and consumers.

-- Resolved once, at file load (library-stack-§4): libs\LibKa0s\LibKa0s.xml loads in the TOC's lib
-- block, long before this file, so the major is either registered by now or absent for good.
local Bus = LibStub and LibStub("LibKa0s-Bus-1.0", true)
if not Bus then
    -- The untracked-target stub (options-ui-§1 names the shape; the Bus API document's "Worked
    -- example" is its text). Receivers still get a private target, so the receiver rule holds, but
    -- nothing is recorded: on an install with LibKa0s missing, a disable leaves the five bus
    -- subscriptions live. docs/ARCHITECTURE.md → Known Limitations states it. It copies nothing of
    -- the library, and it is not this file's old subscription register kept alive as a fallback:
    -- options-ui-§1 does not admit a completing stub for this major.
    Bus = {
        New = function(_, d)
            return {
                name = d and d.name,
                NewTarget = function()
                    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
                    if not AceEvent then return nil end
                    local t = {}
                    AceEvent:Embed(t)
                    return t
                end,
                StandDown = function() return 0 end,
                StandUp   = function() return 0, {} end,
            }
        end,
        Catalog = function(_, messages) return messages end,
    }
end
-- Suite seam only: tests/test_bus.lua holds this table to the live library's surface by name
-- (Kit.assertSurfaceParity), which it can only do on a degraded load if the stub is reachable.
NS.__busLib = Bus

-- The shared publish target. Host code, not the library's: sending is not a registration, so it
-- carries nothing a stand-down needs to know about. AceEvent embeds its :SendMessage mixin here;
-- every embedded object funnels through AceEvent's one message registry, so a SendMessage on NS.bus
-- reaches receivers registered on any target.
local AceEvent = LibStub("AceEvent-3.0")
NS.bus = NS.bus or {}
AceEvent:Embed(NS.bus)

-- ── the stand-down record ─────────────────────────────────────────────────────────────────────
--
-- A RegisterMessage is a REGISTRATION, and slash-commands-§7 names it beside RegisterEvent: a
-- stood-down addon has unregistered it, not gated the handler behind a flag. The subscribing
-- modules hold their targets as file-locals, so the record has to live
-- with the factory that made them. Every target NS.NewBusTarget() hands out is TRACKED: its
-- register and unregister calls are recorded, core/LifecycleSetup.lua's StandDown takes them all down
-- through NS.BusStandDown, and its StandUp replays the record AS IT IS NOW through NS.BusStandUp.
-- A receiver that unregisters while up is forgotten, and one that registers while down is recorded
-- and not made live until the stand-up (both are the library's).
--
-- `isDown` is a closure because the latch does not exist yet: core/LifecycleSetup.lua loads after this
-- file. Inside the latch's own standUp callback it already answers false, so the replay proceeds;
-- anywhere else while a hold is taken it answers true and a bare stand-up of the bus is refused.
NS.busRecord = Bus:New{ name = addonName, isDown = function() return NS.IsStoodDown() end }

--- A fresh tracked AceEvent target, one per receiver (architecture-§4's receiver rule).
function NS.NewBusTarget() return NS.busRecord:NewTarget() end

--- Take every tracked registration down. Answers how many entries the record holds, which is what
--- lets a test tell "there was nothing to drop" from "the record was never populated".
function NS.BusStandDown() return NS.busRecord:StandDown() end

--- Replay the record as it is now. Answers how many entries went live. An entry that raised on the
--- replay is dropped from the record by the library and named here, through the debug seam: the
--- stand-up is inside the latch's callback, so the library never raises out of it.
function NS.BusStandUp()
    local replayed, rejected = NS.busRecord:StandUp()
    -- The list is joined behind the debug gate (debug-logging-§4), not before it.
    if #rejected > 0 and NS.Debug and NS.State and NS.State.debug then
        NS.Debug("Bus", "rejected on stand-up: %s", table.concat(rejected, ", "))
    end
    return replayed
end

-- Message-name catalog. Prefixed Ka0s_<Addon>_ to avoid cross-addon collision, and declared through
-- Catalog, which validates the names at load and answers a STRICT copy: reading a key that is not
-- declared raises at the call site, for a publisher as well as a subscriber.
NS.MSG = Bus.Catalog(addonName, {
    -- Sender: modules/Ticker.lua (Task 2 of the v0.1.0 plan). Payload: (unit, state, minYd, maxYd).
    -- A watched unit's range bracket moved; sent only on change.
    RANGE_UPDATED      = "Ka0s_RangeMaster_RangeUpdated",
    -- Sender: modules/ContainerManager.lua, the registry's one writer. Payload: none. A container
    -- was created, deleted, renamed or duplicated, or the profile under the registry changed.
    CONTAINERS_CHANGED = "Ka0s_RangeMaster_ContainersChanged",
    -- Sender: modules/BandSets.lua. Payload: none. A band set was created, deleted, renamed or
    -- edited.
    BANDSETS_CHANGED   = "Ka0s_RangeMaster_BandSetsChanged",
    -- Sender: modules/Range.lua (the debounced rebuild, dynamic-bands plan D2). Payload: none. A
    -- band rule's resolved anchor spell, its reported range, or the one a druid's form puts in use
    -- moved; sent only on change.
    ANCHORS_CHANGED    = "Ka0s_RangeMaster_AnchorsChanged",
    -- Sender: core/RangeMaster.lua (NS.SetTestMode / NS.SetSimMode). Payload: (mode, on, why), mode
    -- one of "test" or "sim", why the writer's reason ("combat started", "stood down", a surface).
    -- Test mode or Sim mode started or ended.
    MODE_CHANGED       = "Ka0s_RangeMaster_ModeChanged",
})
