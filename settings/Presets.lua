local _, NS = ...
-- settings/Presets.lua — the container presets' surfaces: the General page's Presets tab, the
-- confirm every Apply goes through, the Undo, and the first-run preset picker (design spec 5.2, 5.6;
-- the mockup's presets board).
--
--     General > Presets
--       -- Simple · 4 containers --        what it holds, line by line      [Apply Simple…]
--       -- Intermediate · 4 containers --  ...                              [Apply Intermediate…]
--       -- Advanced · 6 containers --      ...                              [Apply Advanced…]
--       [Undo last preset]
--
-- APPLYING REPLACES THE PROFILE'S CONTAINERS, so it is confirmed first whenever there is anything to
-- replace (the popup names the count); an empty profile has nothing to lose and applies at once. The
-- tab's buttons and `/rm preset <key>` take the same NS.ConfirmPreset, and Undo (the button and
-- `/rm preset undo`) the same NS.UndoPreset. The work is modules/Presets.lua's, through the
-- registries' own writers.
--
-- THE FIRST-RUN PICKER is one prompt per profile while `profile.seeded` is false (modules/Presets.lua's
-- PickerDue): Choose a preset opens the General page on its Presets tab, Not now closes it. It is
-- marked seen as it SHOWS, so a /reload, Escape or a crash never offers it twice on one profile. In
-- combat it waits for PLAYER_REGEN_ENABLED. The first-run skin picker waits behind it, so the two
-- never show at once: OnEnable and every profile event ask this one first (core/RangeMaster.lua).

local L = NS.L
local H = NS.Helpers
local print = NS.Print
local printf = NS.Printf

local Presets = NS.Presets

-- ---------------------------------------------------------------------------
-- Apply, confirm, undo
-- ---------------------------------------------------------------------------

--- Apply preset `key` now: the containers replaced, the first one selected, the picker marked seen.
--- Answers whether it applied.
function NS.ApplyPresetNow(key)
    local d = Presets.Describe(key)
    if not (d and Presets.Apply(key)) then return false end
    Presets.MarkPickerSeen()
    NS.SelectContainer(nil)
    printf(L["%s preset applied: %d range display(s). /rm preset undo puts back what was there."], d.name,
        #NS.CM.List())
    NS.RequestPanelRefresh()
    return true
end

StaticPopupDialogs["RANGEMASTER_APPLY_PRESET"] = {
    text         = L["Apply the %s preset? It replaces this profile's %d range display(s). Undo puts them back."],
    button1      = L["Apply"],
    button2      = L["Cancel"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function(_, data) if data then NS.ApplyPresetNow(data) end end,
}

--- Apply preset `key` behind the confirm (none while the profile has no container). Answers "shown"
--- when the confirm is up, "applied", or nil for an unknown key.
function NS.ConfirmPreset(key)
    local d = Presets.Describe(key)
    if not d then return nil end
    local count = #NS.CM.List()
    if count == 0 then
        NS.ApplyPresetNow(key)
        return "applied"
    end
    local popup = StaticPopup_Show("RANGEMASTER_APPLY_PRESET", d.name, count)
    if popup then popup.data = key end
    return "shown"
end

--- Put back what the last preset replaced. Answers whether there was anything to undo.
function NS.UndoPreset()
    if not Presets.Undo() then
        print(L["No preset to undo."])
        return false
    end
    NS.SelectContainer(nil)
    print(L["Preset undone: the range displays from before are back."])
    NS.RequestPanelRefresh()
    return true
end

-- ---------------------------------------------------------------------------
-- The General page's Presets tab
-- ---------------------------------------------------------------------------

local function renderCard(ctx, key)
    local d = Presets.Describe(key)
    H.Section(ctx, L["%s \194\183 %d containers"]:format(d.name, d.count))
    for _, item in ipairs(d.items) do H.TextRow(ctx, "  " .. item) end
    H.InlineButtonPair(ctx, {
        text = L["Apply %s\226\128\166"]:format(d.name),
        tooltip = L["Replace this profile's containers with this preset. Asks first; Undo last preset puts them back."],
        onClick = function() NS.ConfirmPreset(key) end,
    }, nil)
end

local function renderTab(ctx)
    H.TextRow(ctx, L["Start from a preset. Applying one replaces this profile's containers (you are asked first; Undo restores the previous set). Every container uses your class's default band set."],
        { fontObject = "GameFontHighlightSmall" })
    for _, key in ipairs(Presets.ORDER) do renderCard(ctx, key) end
    H.Section(ctx, L["Undo"])
    H.InlineButtonPair(ctx, {
        text = L["Undo last preset"],
        tooltip = Presets.CanUndo() and L["Put back the containers and band sets the last preset replaced."]
            or L["Nothing to undo: no preset was applied on this profile this session."],
        onClick = function() NS.UndoPreset() end,
    }, nil)
end

-- A host tab (options-ui-§13): presets are acts, not settings, so the tab holds no row and the
-- page's Defaults does not reach it. Placed after Master controls and before the Skin tab.
NS.PRESETS_TAB = {
    key = "Presets", label = L["Presets"],
    tooltip = L["Start from Simple, Intermediate or Advanced, and undo it."],
    render = function(ctx) renderTab(ctx) end,
}

-- ---------------------------------------------------------------------------
-- The first-run picker
-- ---------------------------------------------------------------------------

local holdTarget   -- the one-shot PLAYER_REGEN_ENABLED target while a showing waits out combat

local function dropHold()
    if not holdTarget then return end
    holdTarget:UnregisterEvent("PLAYER_REGEN_ENABLED")
    holdTarget = nil
end

StaticPopupDialogs["RANGEMASTER_PRESET_PICKER"] = {
    text         = L["Welcome to Range Master. Start from a preset (Simple, Intermediate or Advanced) or build your own containers. You can change everything later."],
    button1      = L["Choose a preset"],
    button2      = L["Not now"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function() NS.OpenGeneralTab("Presets") end,
    -- The skin picker waited behind this one; it is offered once this closes, however it closed.
    OnHide       = function() if NS.MaybeShowSkinPicker then NS.MaybeShowSkinPicker() end end,
}

--- Show the first-run picker when it is owed on this profile and the addon stands up; in combat, hold
--- it for PLAYER_REGEN_ENABLED. Answers true when it showed or is held (the skin picker then waits).
function NS.MaybeShowPresetPicker()
    if not Presets.PickerDue() or NS.IsStoodDown() then
        dropHold()
        return false
    end
    if InCombatLockdown() then
        if holdTarget then return true end
        holdTarget = NS.NewBusTarget and NS.NewBusTarget()
        if not holdTarget then return false end
        NS.SafeRegisterEvent(holdTarget, "PLAYER_REGEN_ENABLED", function()
            dropHold()
            NS.MaybeShowPresetPicker()
        end, NS.State.rejectedEvents)
        return true
    end
    Presets.MarkPickerSeen()
    NS.Debug("Presets", "first-run picker shown")
    StaticPopup_Show("RANGEMASTER_PRESET_PICKER")
    return true
end

--- Take the picker down unanswered and drop a held showing: the stand-down and every profile event.
function NS.HidePresetPicker()
    dropHold()
    if StaticPopup_Hide then StaticPopup_Hide("RANGEMASTER_PRESET_PICKER") end
end

--- Open the General page on tab `tabKey`. Refused in combat by the open itself (options-ui-§2).
function NS.OpenGeneralTab(tabKey)
    NS.__generalTab = tabKey
    if NS.OpenOptionsPanel("general") == false then
        NS.__generalTab = nil
        return false
    end
    if H.SelectTab and H.SelectTab("general", tabKey) then NS.__generalTab = nil end
    return true
end

-- Suite seam (tests/test_settings_presets.lua).
function NS.__presetPickerHeld() return holdTarget ~= nil end
