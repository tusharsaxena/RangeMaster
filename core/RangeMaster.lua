local addonName, NS = ...
-- core/RangeMaster.lua — the AceAddon, its lifecycle, the game events the addon itself hears, the two
-- preview modes (Test mode and Sim mode) and the AceDB profile callbacks.

-- The perf probe, taken as a load-time upvalue (core/PerfSetup.lua loads earlier), so a dormant
-- bracket costs one upvalue read and one field read (performance-§2).
local Perf = NS.Perf

-- AceAddon promotion (architecture-§2): NS is passed in, so the namespace and the addon are one table.
local AceAddon = LibStub("AceAddon-3.0")
local addon = AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
NS.addon = addon

-- Reclaim NS.Print and NS.Printf from AceConsole's embed, which stamps its own :Print and :Printf
-- over ours (architecture-§2, anti-pattern #36). core/CoreSetup.lua stashed the real printers at
-- NS.Util.print and NS.Util.printf, the same objects every settings file captured.
if NS.Util and NS.Util.print then NS.Print = NS.Util.print end
if NS.Util and NS.Util.printf then NS.Printf = NS.Util.printf end

local L = NS.L

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function addon:OnInitialize()
    NS:InitDB()
    -- The profile's skin, applied as soon as the store exists (skinning-§2): the owner registered at
    -- file load wearing the client default, before AceDB, and nothing has been drawn for it yet.
    NS.ApplySkinChoice()
    if NS.Slash and NS.Slash.Register then NS.Slash:Register() end
    -- AFTER InitDB, never before: the launcher is handed `db.global.minimap`, which AceDB
    -- materializes from the declared default there.
    if NS.Launcher then NS.Launcher:Register() end
end

--- The two first-run prompts, one at a time: the preset picker first (settings/Presets.lua), and the
--- skin picker only when that one is not up or held; its close offers the skin picker then.
local function showFirstRunPickers()
    if NS.MaybeShowPresetPicker and NS.MaybeShowPresetPicker() then return end
    if NS.MaybeShowSkinPicker then NS.MaybeShowSkinPicker() end
end

function addon:OnEnable()
    NS.ClearLSMCache()
    NS.GetLSM()
    -- THE HOLD IS TAKEN FROM THE STORED PATH, here, before anything registers. The same call the
    -- checkbox, the two verbs and the profile callbacks make (core/LifecycleSetup.lua).
    NS.SyncEnabledHold()
    -- The panel and the dispatcher are SETUP and come up in either state; the events are a FEATURE
    -- and come up only if the addon is actually running (slash-commands-§7).
    if not NS.IsStoodDown() then self:RegisterLifecycleEvents() end
    -- The stored containers draw now, whatever the skin did: the skin's OnLooksChanged is no trigger
    -- for the first apply. Stood down, this only marks the apply owed; the stand-up's CM.StandUp runs it.
    NS.CM.RequestApply()
    if NS.CreateOptionsPanel then NS.CreateOptionsPanel() end
    showFirstRunPickers()
end

--- Every event the addon itself registers, and the method each calls. ONE list, read by both the
--- stand-up and the stand-down, so the two cannot drift apart.
--- `ifValid` marks an event some client the TOC admits may not carry (PLAYER_FOCUS_CHANGED on WoW
--- Forever, design spec 3): it is registered only where NS.Compat.IsEventValid says the client knows
--- it, so a focus-less client skips it rather than recording a rejection.
local LIFECYCLE_EVENTS = {
    { "PLAYER_ENTERING_WORLD", "OnEnterWorld" },
    { "PLAYER_REGEN_DISABLED", "OnCombatChanged" },
    { "PLAYER_REGEN_ENABLED",  "OnCombatChanged" },
    -- The range engine's forced refreshes (design spec 5.1): each re-reads its unit at once,
    -- between ticks, and starts the ticker if the unit is watched and exists.
    { "PLAYER_TARGET_CHANGED", "OnUnitChanged" },
    { "PLAYER_FOCUS_CHANGED",  "OnUnitChanged", ifValid = true },
    { "UPDATE_MOUSEOVER_UNIT", "OnUnitChanged" },
    { "UNIT_PET",              "OnPetChanged" },
    { "NAME_PLATE_UNIT_ADDED",   "OnNamePlateChanged" },
    { "NAME_PLATE_UNIT_REMOVED", "OnNamePlateChanged" },
    -- A unit's reaction moved (a mob turning hostile, a duel): the band set a container reads
    -- depends on it (design spec 5.3, bandSetFriendly), so it is a unit change like a retarget.
    { "UNIT_FACTION",          "OnUnitFaction", ifValid = true },
    -- Learned, unlearned or swapped spells: the ladder and the known-spell cache, debounced.
    { "SPELLS_CHANGED",        "OnSpellsChanged" },
    -- An addon loaded: a unit frame a container waits for may exist now (modules/Anchors_Frame.lua).
    { "ADDON_LOADED",          "OnAddonLoaded" },
}
-- Suite seam: tests/test_disabled.lua and tests/test_events.lua read the list the code registers.
NS.__lifecycleEvents = LIFECYCLE_EVENTS

--- Each registration goes through NS.SafeRegisterEvent: a name this client does not know costs only
--- itself and is recorded in NS.State.rejectedEvents (events-frames-taint-§1), traced once.
function addon:RegisterLifecycleEvents()
    for _, pair in ipairs(LIFECYCLE_EVENTS) do
        if not pair.ifValid or NS.Compat.IsEventValid(pair[1]) then
            if not NS.SafeRegisterEvent(self, pair[1], pair[2], NS.State.rejectedEvents) then
                NS.DebugOnce("rejected:" .. pair[1], "Events", "rejected %s", pair[1])
            end
        end
    end
end

function addon:UnregisterLifecycleEvents()
    for _, pair in ipairs(LIFECYCLE_EVENTS) do
        self:UnregisterEvent(pair[1])
    end
end

--- The unit each forced-refresh event names (design spec 5.1).
local EVENT_UNIT = {
    PLAYER_TARGET_CHANGED = "target",
    PLAYER_FOCUS_CHANGED  = "focus",
    UPDATE_MOUSEOVER_UNIT = "mouseover",
}

--- A different unit sits behind the token now: every container on it forgets what it drew (the band
--- set, the band, the class color and the spell answers all belong to the old unit), and the ticker
--- re-reads the token and sends its triple even when the bracket did not move.
local function unitChanged(unit)
    NS.Container.UnitChanged(unit)
    -- The anchors that follow a token: an own-plate container moves to the new unit's plate, and a
    -- plate token's eligibility for the `nameplates` containers is asked again (a reaction change).
    NS.Anchors.UnitChanged(unit)
    NS.Ticker.Changed(unit)
end

function addon:OnUnitChanged(event)
    local unit = EVENT_UNIT[event]
    if unit then unitChanged(unit) end
end

--- UNIT_PET names the OWNER whose pet changed; only the player's is the `pet` token.
function addon:OnPetChanged(_, owner)
    if owner == "player" then unitChanged("pet") end
end

--- UNIT_FACTION names the unit whose reaction moved; only a watched one reaches anything.
function addon:OnUnitFaction(_, unit)
    if type(unit) == "string" and NS.Compat.IsSafeKey(unit) then unitChanged(unit) end
end

--- A plate came or went. The plate registry hears it first (modules/Anchors_Nameplate.lua: a plate
--- instance built or parked, the own-plate containers placed), then the range: an added plate's token
--- is re-read, a removed one is sent as "none" outright, because the client still resolves the token
--- while NAME_PLATE_UNIT_REMOVED dispatches and a re-read would see the plate as live. The plate
--- registry's park has normally dropped the token's last watch already, so Ticker.Removed is the
--- guard for any other watcher of it (modules/Ticker.lua says why it stays).
function addon:OnNamePlateChanged(event, token)
    if type(token) ~= "string" or not NS.Compat.IsSafeKey(token) then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        NS.Plates.Removed(token)
        NS.Ticker.Removed(token)
    else
        NS.Plates.Added(token)
        unitChanged(token)
    end
end

--- Any addon loading may have created a unit frame a container waits for.
function addon:OnAddonLoaded(_, name)
    NS.Anchors.Frame.Retry(name)
end

function addon:OnSpellsChanged()
    NS.Range.Rebuild()
end

function addon:OnEnterWorld(_, isLogin, isReload)
    NS.Debug("World", "entering world (%s)",
        isLogin and "login" or isReload and "reload" or "zone change")
    -- EllesmereUI spawns its unit frames at PLAYER_LOGIN, after this addon's first apply may have run.
    NS.Anchors.Frame.Retry("PLAYER_ENTERING_WORLD")
end

--- The combat edge. Both preview modes end when combat starts, while secure writes are still
--- allowed (preview-mode): no placeholder covers a real range in a fight. The range ticker is
--- re-armed at the edge's rate, and the leave edge runs a container apply combat held.
function addon:OnCombatChanged(event)
    local t0 = Perf.on and debugprofilestop()
    local entering = event == "PLAYER_REGEN_DISABLED"
    local ended = entering and NS.EndModes("combat started") or 0
    -- A frame pick never runs in combat (modules/FramePicker.lua).
    if entering then NS.FramePicker.Cancel("combat") end
    -- A preset preview is the player's set swapped out; it goes back when a fight starts.
    if entering and NS.PresetPickerCombat then NS.PresetPickerCombat() end
    -- The range ticker's rate follows the edge: 20 Hz in combat, 10 Hz out of it.
    NS.Ticker.SetCombat(entering)
    -- The visibility rules read the edge (modules/Visibility.lua): every container's combat rule and
    -- out-of-combat opacity are asked again. Own frames only: a show, a hide or an opacity.
    NS.Visibility.SetCombat(entering)
    NS.Container.RefreshVisibility()
    -- A container apply held by combat runs on the leave edge (modules/ContainerManager.lua).
    if not entering then
        NS.CM.FlushPending("regen")
        -- An anchor write onto a unit frame that combat held (modules/Anchors_Frame.lua).
        NS.Anchors.FlushDeferred()
    end
    NS.Debug("Combat", entering and "entered: %s preview mode(s) ended" or "left", ended)
    if t0 then Perf.Note("combatEdge", debugprofilestop() - t0) end
end

-- ---------------------------------------------------------------------------
-- Test mode and Sim mode (preview-mode, options-ui-§15)
-- ---------------------------------------------------------------------------
--
-- Session state in NS.State (never in SavedVariables), each with ONE writer below. Every surface
-- reaches it through that writer: the Master controls checkboxes (settings/General.lua), the launcher
-- menu (core/LauncherSetup.lua), `/rm test` and `/rm sim` (settings/Slash.lua) and the skin picker's
-- eye (core/SkinSetup.lua). A start is refused in combat and while the addon stands down; combat
-- and a stand-down end both. Test mode is also refused while a sim runs (the Sim major's H5). What
-- each mode DRAWS is modules/Preview.lua's and modules/Sim.lua's, both subscribed to MODE_CHANGED,
-- whose payload is (mode, on, why).

local MODE_FIELD = { test = "testMode", sim = "simMode" }

--- Why a mode cannot start right now, as the gray line to print, or nil.
local function startRefusal(mode)
    if InCombatLockdown() then
        return L["Cannot start a preview mode during combat."]
    end
    if NS.IsStoodDown() then
        return L["Cannot start a preview mode while Range Master is stood down."]
    end
    if mode == "test" and NS.State.simMode then
        return L["Cannot start Test mode while Sim mode runs."]
    end
end

--- Set one mode. Answers true when the mode is now `on`, false when the start was refused. A no-op
--- write answers true and sends nothing.
local function setMode(mode, on, why)
    local field = MODE_FIELD[mode]
    on = on and true or false
    if NS.State[field] == on then return true end
    if on then
        local refusal = startRefusal(mode)
        if refusal then
            NS.Printf("|cff808080%s|r", refusal)
            NS.Debug("Mode", "%s start refused (%s)", mode, refusal)
            return false
        end
    end
    NS.State[field] = on
    NS.Debug("Mode", "%s %s (%s)", mode, on and "on" or "off", tostring(why or "?"))
    NS.bus:SendMessage(NS.MSG.MODE_CHANGED, mode, on, why)
    if NS.RefreshOptionsPanel then NS.RefreshOptionsPanel() end
    return true
end

--- The one writer of Test mode. @return boolean  false when a start was refused
function NS.SetTestMode(on, why) return setMode("test", on, why) end
--- The one writer of Sim mode. @return boolean  false when a start was refused
function NS.SetSimMode(on, why) return setMode("sim", on, why) end

function NS.IsTestMode() return NS.State.testMode == true end
function NS.IsSimMode() return NS.State.simMode == true end

--- The launcher's and the Master controls box's toggles: the slash verbs' own handlers, so the menu,
--- the box and the verb confirm and refuse alike (launcher-§2). Resolved at call time.
function NS.ToggleTestMode() NS.Slash.ToggleTestMode() end
function NS.ToggleSimMode() NS.Slash.ToggleSimMode() end

--- End both modes (combat, a stand-down). Answers how many were on.
function NS.EndModes(why)
    local n = 0
    for mode, field in pairs(MODE_FIELD) do
        if NS.State[field] then
            setMode(mode, false, why)
            n = n + 1
        end
    end
    return n
end

--- Move every range display back to its default position: the Master controls Reset position button
--- and `/rm resetposition`, one handler. Every container free on screen goes back to the point a new
--- container takes (NS.CM.ResetPosition); a container on a frame, a plate or the cursor has no screen
--- position to reset. Answers how many moved.
function NS.ResetPositions()
    local n = 0
    for _, id in ipairs(NS.CM.List()) do
        local c = NS.CM.Get(id)
        if c and c.anchor and c.anchor.mode == "screen" and NS.CM.ResetPosition(id) then n = n + 1 end
    end
    NS.Debug("Position", "reset %s display position(s)", n)
    return n
end

-- ---------------------------------------------------------------------------
-- The AceDB profile callbacks (core/Database.lua)
-- ---------------------------------------------------------------------------
--
-- A switch, a reset or a copy is AceDB replacing the profile whole, not a write through the seam, so
-- each is traced ONCE here in its own words (debug-logging-§10). A switch can flip the enable path
-- with no checkbox touched, so the latch is re-read from the new profile: this is why a disabled
-- addon keeps AceDB's three callbacks (slash-commands-§7).

local function currentProfile()
    return (NS.db and NS.db.GetCurrentProfile and NS.db:GetCurrentProfile()) or "?"
end

local function adoptProfile(tag, fmt, ...)
    NS.Debug(tag, fmt, ...)
    -- The picker goes down first, unmarked: its dismissal puts back the OLD profile's skin, so it
    -- must go before the new profile's skin is applied.
    if NS.HideSkinPicker then NS.HideSkinPicker() end
    if NS.HidePresetPicker then NS.HidePresetPicker() end
    NS:RunMigrations()
    -- The registries are the new profile's now: a preset's Undo slot was the old one's, and the
    -- renderer hears the new containers through the registry's own sender (modules/ContainerManager).
    if NS.Presets and NS.Presets.ForgetUndo then NS.Presets.ForgetUndo() end
    NS.ApplySkinChoice()
    NS.SyncEnabledHold()
    if NS.CM and NS.CM.RequestApply then NS.CM.RequestApply() end
    -- The selections named the old profile's containers and band sets.
    NS.SelectContainer(nil)
    NS.SelectBandSet(nil)
    showFirstRunPickers()
    if NS.RefreshOptionsPanel then NS.RefreshOptionsPanel() end
end

function NS.OnProfileChanged()
    adoptProfile("Profile", "changed -> %s", currentProfile())
end

--- AceDB's OnProfileShutdown (a switch, while the old profile is still the active one) and
--- OnDatabaseShutdown (a logout or a /reload, before SavedVariables are written): the preset picker
--- goes down, its preview restored into the profile it was taken on (settings/Presets.lua).
function NS.OnProfileShutdown()
    if NS.HidePresetPicker then NS.HidePresetPicker() end
end

function NS.OnProfileReset()
    -- The profile was replaced whole: a preset preview in it is dropped, not restored over it.
    if NS.HidePresetPicker then NS.HidePresetPicker(true) end
    local n = NS.ConsumeResetCount and NS.ConsumeResetCount()
    if n then
        adoptProfile("Set", "reset profile '%s' to defaults (%s rows)", currentProfile(), n)
    else
        adoptProfile("Set", "reset profile '%s' to defaults", currentProfile())
    end
end

function NS.OnProfileCopied(source)
    if NS.HidePresetPicker then NS.HidePresetPicker(true) end
    adoptProfile("Set", "copied profile '%s' -> '%s'", tostring(source or "?"), currentProfile())
end
