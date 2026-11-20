local addonName, NS = ...
-- settings/Presets.lua — the container presets' surfaces: the General page's Presets tab, the
-- confirm every Apply goes through, the Undo, and the first-run preset picker (design spec 5.2, 5.6;
-- the mockup's presets board).
--
--     General > Presets
--       -- Simple · 4 containers --        what it holds, line by line      [Apply Simple…]
--       -- Intermediate (Range Text) · 4 containers --  ...                 [Apply Intermediate (Range Text)…]
--       -- Intermediate (Range Numbers) · 4 containers --  ...              [Apply Intermediate (Range Numbers)…]
--       -- Advanced · 4 containers --      ...                              [Apply Advanced…]
--       -- Expert · 6 containers --        ...                              [Apply Expert…]
--       [Undo last preset]
--
-- APPLYING REPLACES THE PROFILE'S CONTAINERS, so it is confirmed first whenever there is anything to
-- replace (the popup names the count); an empty profile has nothing to lose and applies at once. The
-- tab's buttons and `/rm preset <key>` take the same NS.ConfirmPreset, and Undo (the button and
-- `/rm preset undo`) the same NS.UndoPreset. The work is modules/Presets.lua's, through the
-- registries' own writers.
--
-- THE PRESET PICKER is a window of its own, shaped as AuraMaster's (below): a dropdown of the five
-- presets, each pick previewed on the real screen in test mode, Apply and Not now. It shows once per
-- profile while `profile.seeded` is false (modules/Presets.lua's PickerDue), marked seen as it SHOWS,
-- and on demand from `/rm preset`. The first-run skin picker waits behind it, so the two never show
-- at once: OnEnable and every profile event ask this one first (core/RangeMaster.lua).

local L = NS.L
local H = NS.Helpers
local print = NS.Print
local printf = NS.Printf

local Presets = NS.Presets

local pending   -- the picker's open confirm ({ run }), nil while none is up (its Apply, below)

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
    -- `data` is a preset key (the tab, `/rm preset <key>`), or the picker's { run } (its Apply).
    OnAccept     = function(_, data)
        if type(data) == "table" then
            if type(data.run) == "function" then data.run() end
        elseif data then
            NS.ApplyPresetNow(data)
        end
    end,
    OnHide       = function(self) if self and self.data == pending then pending = nil end end,
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
    tooltip = L["Start from one of the six presets, and undo it."],
    render = function(ctx) renderTab(ctx) end,
}

-- ---------------------------------------------------------------------------
-- The preset picker window
-- ---------------------------------------------------------------------------
--
-- AuraMaster's picker, shaped for this addon (its settings/PresetPicker.lua):
--
--     Choose a preset                              [gear][x]
--     Ka0s Range Master
--     [Simple - 4 containers                  v]
--     what the preset holds, in a line or two
--     The skin picker opens next.                  <- while that one is still due
--     On your screen now, in test mode. ...        <- while a pick is previewed
--     [Containers: unlocked] [Test mode: on]
--     [Apply                       ] [Not now]
--     -- Change it later on General > Presets. --  <- the footer
--
-- OPENING records the lock, unlocks the containers and turns test mode on, so a pick is seen where
-- it lands. A PICK previews the preset on the real screen (NS.Presets.BeginPreview). On a profile
-- with no containers of its own (a new one) the window previews Simple, its selection, as it opens,
-- so the screen is never empty under it; one with containers keeps them on screen until a pick. APPLY keeps the pick behind the confirm when the player has
-- containers of their own (the window stays up under it), then locks and turns test mode off; with
-- nothing picked it keeps what is there. NOT NOW, the close mark and Escape restore the player's set
-- and put back the lock the window found. Every close the player makes offers the skin picker next,
-- except the settings mark's, which opens General > Presets (the skin picker is modal and would cover
-- the panel; it stays due). This addon's own hides (NS.HidePresetPicker: the stand-down, a profile
-- event, AceDB's shutdowns) restore too, offer nothing and leave the skin picker alone.
--
-- THE FIRST-RUN SHOWING is one per profile while `profile.seeded` is false (Presets.PickerDue). It
-- is marked seen as it SHOWS, so a /reload, Escape or a crash never offers it twice on one profile;
-- in combat it waits for PLAYER_REGEN_ENABLED. `/rm preset` opens it on demand. Combat starting while
-- it is up restores a preview (NS.PresetPickerCombat, from core/RangeMaster.lua's combat edge).
--
-- BUILT FROM THE LIBRARY'S PIECES, as AuraMaster's: the shell and close through core/CoreSetup.lua's
-- seams (NS.ApplySkin, NS.MakeCloseButton), the dropdown, the header marks and the footer
-- LibKa0s-Widgets-1.0's, every button and string painted through the skin facade (NS.Skin), each
-- guarded so a degraded install draws stock frames. MODAL strata, the skin picker's
-- (frame-layering-§1); toplevel, and on show it re-raises any shown StaticPopup (frame-layering-§4).

local KW = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
local KC = LibStub and LibStub("LibKa0s-Core-1.0", true)

local WINDOW = "RangeMasterPresetPicker"
local WIDTH, PAD, ROW_H, GAP = 300, 14, 22, 8
-- Where the LibKa0s skin picker opens (OptionsSkinPicker.lua's HEIGHT_SHARE): the two never show at
-- once, so they share the spot.
local HEIGHT_SHARE = 0.75
local FOOTER_FALLBACK_H = 24   -- W.FOOTER.HEIGHT, for an install without the library

local BLURBS = {
    simple   = L["Target, focus, pet and mouseover, free on screen: a dot in the band's color."],
    text     = L["Target, focus, pet and mouseover, free on screen: the band's label as text."],
    numbers  = L["Target, focus, pet and mouseover, free on screen: the range number."],
    advanced = L["Target, focus, pet and mouseover, free on screen: dot, range number and label."],
    expert   = L["Advanced with spell chips, a healer set for friends, an out-of-range sound and combat nameplate markers."],
    ka0s     = L["The author's own setup: range number above band name for any unit, no frame, a healer set for friends, and the number on the target's nameplate, moving to its cast bar while it casts. No sounds."],
}

-- The window's session state: `sel` what the dropdown shows, `picked` whether the player chose
-- anything since it opened, `lockedAtOpen` the lock it found and `lockProfile` the profile it found
-- it in (nil while down), `open` whether this showing has not closed yet.
local state = { sel = "simple", picked = false, lockedAtOpen = true, lockProfile = nil, open = false }
local closing = false     -- true while this file hides the window itself, so OnHide is not a close
local toSettings = false  -- true while the settings mark closes it: no skin picker over the panel
local holdTarget          -- the one-shot PLAYER_REGEN_ENABLED target while a showing waits out combat

NS.PresetPicker = NS.PresetPicker or {}
local Picker = NS.PresetPicker

local function sayGray(msg) printf("|cff808080%s|r", msg) end

--- Call the skin facade's `member` when it has one (the degraded facade has no Button or Header).
local function paint(member, ...)
    local fn = NS.Skin and NS.Skin[member]
    if type(fn) == "function" then return fn(...) end
end

local function choiceLabel(key)
    local d = Presets.Describe(key)
    return L["%s - %d containers"]:format(d.name, d.count)
end

-- ── the lock and test mode ───────────────────────────────────────────────────────────────────

local refresh       -- below: repaints the window from `state`
local paintToggles  -- below: the lock and test-mode buttons' labels

--- Write the lock through the seam `/rm lock` and `/rm unlock` write.
local function setLock(locked)
    local ok, err = NS.SetByPath("locked", locked and true or false)
    if not ok and err then print(err) end
end

local function testMode(on)
    if NS.IsTestMode() ~= on then NS.SetTestMode(on, "preset picker") end
end

--- Record the lock the window opens on, then unlock and turn test mode on.
local function openUnlocked()
    state.lockedAtOpen = NS.GetSetting("locked") and true or false
    state.lockProfile = NS.db and NS.db.profile
    setLock(false)
    testMode(true)
end

--- What every close ends with: test mode off, then the lock set to `locked`, in the profile the
--- window opened on only. `replaced` (a reset or a copy) writes no lock: the profile is not the one
--- the window found.
local function settle(locked, replaced)
    testMode(false)
    local same = state.lockProfile ~= nil and NS.db and NS.db.profile == state.lockProfile
    state.lockProfile = nil
    if same and not replaced then setLock(locked) end
end

local function toggleLock()
    setLock(not NS.GetSetting("locked"))
    refresh()
end

--- The test-mode button. Off with a preview up ends it with a restore, as Not now does.
local function toggleTest()
    if not NS.IsTestMode() then
        testMode(true)
    else
        if Presets.EndPreview(false) then state.picked = false end
        testMode(false)
    end
    refresh()
end

-- ── the confirm ──────────────────────────────────────────────────────────────────────────────

--- Take an open confirm of the window's down unanswered: what it would have run never runs.
local function dropConfirm()
    local data = pending
    if not data then return end
    pending = nil
    data.run = nil
    if StaticPopup_Hide then StaticPopup_Hide("RANGEMASTER_APPLY_PRESET") end
end

-- ── picking, applying, closing ───────────────────────────────────────────────────────────────

local function pick(key)
    if not BLURBS[key] then return end
    if InCombatLockdown() then
        sayGray(L["cannot preview a preset during combat; pick again once combat ends"])
        return refresh()
    end
    state.sel = key
    if Presets.BeginPreview(key) then
        state.picked = true
        NS.SelectContainer(nil)
        testMode(true)
        if NS.GetSetting("locked") then setLock(false) end
    end
    refresh()
end

--- The player's close of any kind: the window down with its confirm, test mode off and the lock set
--- to `locked`, the unlock hint once per showing, then the skin picker's turn.
local function finish(locked)
    dropConfirm()
    settle(locked)
    closing = true
    if Picker.frame then Picker.frame:Hide() end
    closing = false
    state.picked = false
    if state.open then print(L["Type /rm unlock to move your range displays."]) end
    state.open = false
    if not toSettings and NS.MaybeShowSkinPicker then NS.MaybeShowSkinPicker() end
end

--- Not now, the close mark, Escape: a preview up is restored.
local function dismiss()
    if Presets.IsPreviewing() then
        Presets.EndPreview(false)
        NS.SelectContainer(nil)
        NS.RequestPanelRefresh()
    end
    finish(state.lockedAtOpen)
end

--- Keep preset `key`, decided when the answer is given: the preview when it is still `key`, else
--- `key` applied afresh (combat restored the preview since).
local function keep(key)
    local d = Presets.Describe(key)
    if Presets.Previewed() == key then Presets.EndPreview(true) else Presets.Apply(key) end
    Presets.MarkPickerSeen()
    NS.SelectContainer(nil)
    printf(L["%s preset applied: %d range display(s). /rm preset undo puts back what was there."], d.name,
        #NS.CM.List())
    NS.RequestPanelRefresh()
    finish(true)
end

local function apply()
    if not state.picked then return finish(true) end
    local key = state.sel
    local count = Presets.OwnContainerCount()
    if count == 0 then return keep(key) end
    local popup = StaticPopup_Show("RANGEMASTER_APPLY_PRESET", Presets.Describe(key).name, count)
    if popup then
        pending = { run = function() keep(key) end }
        popup.data = pending
    end
end

--- The settings mark: the window goes down as Not now does (no skin picker over the panel), then
--- the General page opens on its Presets tab.
local function openSettings()
    if state.open then
        toSettings = true
        dismiss()
        toSettings = false
    end
    NS.OpenGeneralTab("Presets")
end

-- ── building the window ──────────────────────────────────────────────────────────────────────

local function fontString(f, template, role)
    local fs = f:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    paint("Text", fs, role or "body")
    return fs
end

local function textButton(f, text, onClick, opts)
    local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
    btn:SetHeight(ROW_H)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    btn.text = fs
    btn:SetScript("OnClick", function() onClick() end)
    paint("Button", btn, opts)
    return btn
end

--- The preset dropdown: LibKa0s-Widgets-1.0's, or, without it, a button that steps through the
--- presets, so a degraded install can still pick.
local function buildDropdown(f)
    local width = WIDTH - 2 * PAD
    local dd
    if KW and KW.Dropdown then
        local options = {}
        for _, key in ipairs(Presets.ORDER) do options[#options + 1] = { value = key, label = choiceLabel(key) } end
        dd = KW.Dropdown(f, width, { owner = addonName, chevron = NS.Icon and NS.Icon("chevron-down") or nil })
        dd:SetOptions(options)
    else
        dd = textButton(f, "", function() end)
        dd:SetWidth(width)
        dd.SetValue = function(self, _, label) self.text:SetText(label or "") end
        dd:SetScript("OnClick", function(self)
            local at = 1
            for i, key in ipairs(Presets.ORDER) do if key == state.sel then at = i end end
            self.onSelect(Presets.ORDER[at % #Presets.ORDER + 1])
        end)
    end
    dd:SetHeight(ROW_H)
    dd.onSelect = function(value) pick(value) end
    f.dd = dd
end

local function plainClose(parent, onClick)
    local btn = textButton(parent, "x", onClick)
    btn:SetWidth(ROW_H)
    return btn
end

--- The title marks: LibKa0s-Widgets-1.0's HeaderButtons, settings · close, in the top-right corner;
--- without them (a degraded install) the close alone, placed by hand.
local function buildMarks(f)
    if KW and type(KW.HeaderButtons) == "function" then
        local hb = KW.HeaderButtons(f, { owner = addonName, frame = f, point = "TOPRIGHT", y = -6,
            makeClose = function(parent, onClick)
                return NS.MakeCloseButton(parent, onClick) or plainClose(parent, onClick)
            end,
            close = function() dismiss() end, settings = openSettings })
        f.close, f.settings = hb.close, hb.settings
        return hb.right
    end
    f.close = NS.MakeCloseButton(f, function() dismiss() end) or plainClose(f, function() dismiss() end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    return { f.close }
end

local function buildChrome(f)
    f.title = fontString(f, "GameFontNormal", "heading")
    f.title:SetText(L["Choose a preset"])
    local right = buildMarks(f)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -10)
    paint("Header", f, { title = f.title, right = right })
    f.owner = fontString(f, "GameFontNormal", "heading")
    f.owner:SetText("Ka0s Range Master")
end

local function footerHeight()
    local F = KW and KW.FOOTER
    return type(F) == "table" and tonumber(F.HEIGHT) or FOOTER_FALLBACK_H
end

--- The footer: the library's W.Footer on the bottom edge, its left line the "change it later" hint;
--- without the library a bare frame of the same height with the same `SetLeft`.
local function buildFooter(f)
    if KW and type(KW.Footer) == "function" then
        f.footer = KW.Footer(f, { owner = addonName })
        return
    end
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    foot:SetHeight(FOOTER_FALLBACK_H)
    foot.left = fontString(foot, "GameFontHighlightSmall", "muted")
    foot.left:SetPoint("LEFT", foot, "LEFT", 8, 0)
    foot.left:SetPoint("RIGHT", foot, "RIGHT", -8, 0)
    foot.SetLeft = function(self, text) self.left:SetText(type(text) == "string" and text or "") end
    f.footer = foot
end

local function buildBody(f)
    buildDropdown(f)
    f.blurb = fontString(f, "GameFontHighlightSmall")
    f.nextHint = fontString(f, "GameFontHighlightSmall", "muted")
    f.nextHint:SetText(L["The skin picker opens next."])
    -- A row of its own, so the line shows and hides as one frame while a preview is up.
    f.status = CreateFrame("Frame", nil, f)
    f.status.text = fontString(f.status, "GameFontNormalSmall", "accent")
    f.status.text:SetAllPoints(f.status)
    f.status.text:SetText(L["On your screen now, in test mode. Nothing is kept until Apply."])
    f.lockToggle = textButton(f, "", function() toggleLock() end)
    f.testToggle = textButton(f, "", function() toggleTest() end)
    f.apply = textButton(f, L["Apply"], function() apply() end, { primary = true })
    f.notNow = textButton(f, L["Not now"], function() dismiss() end)
    buildFooter(f)
end

local function build()
    local f = CreateFrame("Frame", WINDOW, UIParent, "BackdropTemplate")
    Picker.frame = f
    f:Hide()
    f:SetWidth(WIDTH)
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.MODAL)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- Escape (UISpecialFrames) hides it: a close. A hide of UIParent (Alt-Z) fires OnHide with the
    -- window still shown, and a hide this file makes itself is not the player's: neither is a close.
    f:SetScript("OnHide", function(self)
        if closing or (self.IsShown and self:IsShown()) then return end
        dismiss()
    end)
    NS.ApplySkin(f)
    buildChrome(f)
    buildBody(f)
    local specials = _G.UISpecialFrames
    if type(specials) == "table" then table.insert(specials, WINDOW) end
    -- Test mode switched elsewhere (`/rm test`, the launcher, combat) repaints the buttons.
    local ev = NS.NewBusTarget and NS.NewBusTarget()
    if ev then
        ev:RegisterMessage(NS.MSG.MODE_CHANGED, function() if f:IsShown() then paintToggles(f) end end)
    end
    return f
end

-- ── laying it out ────────────────────────────────────────────────────────────────────────────

--- One row under the last: `region` placed `h` tall, a GAP below the previous row.
local function stack(f, y, region, h, x, w)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", f, "TOPLEFT", x or PAD, -y)
    region:SetWidth(w or (WIDTH - 2 * PAD))
    region:SetHeight(h)
    return y + h + GAP
end

local function layout(f)
    local half = (WIDTH - 2 * PAD) / 2
    local y = stack(f, 34, f.owner, 16)
    y = stack(f, y, f.dd, ROW_H)
    y = stack(f, y, f.blurb, 30)
    if f.nextHint:IsShown() then y = stack(f, y, f.nextHint, 14) end
    if f.status:IsShown() then y = stack(f, y, f.status, 28) end
    stack(f, y, f.lockToggle, ROW_H, PAD, half - 3)
    y = stack(f, y, f.testToggle, ROW_H, PAD + half + 3, half - 3)
    local applyW = WIDTH - 2 * PAD - 90 - 6
    stack(f, y, f.apply, ROW_H, PAD, applyW)
    y = stack(f, y, f.notNow, ROW_H, PAD + applyW + 6, 90)
    f:SetHeight(y + footerHeight())
end

function paintToggles(f)
    f.lockToggle.text:SetText(NS.GetSetting("locked") and L["Containers: locked"] or L["Containers: unlocked"])
    f.testToggle.text:SetText(NS.IsTestMode() and L["Test mode: on"] or L["Test mode: off"])
end

function refresh()
    local f = Picker.frame
    if not f then return end
    if f.dd.SetValue then f.dd:SetValue(state.sel, choiceLabel(state.sel)) end
    f.blurb:SetText(BLURBS[state.sel])
    f.status:SetShown(state.picked and Presets.IsPreviewing())
    paintToggles(f)
    f.nextHint:SetShown((NS.SkinPickerDue and NS.SkinPickerDue()) and true or false)
    f.footer:SetLeft(L["Change it later on General > Presets."])
    layout(f)
end

-- ── showing and hiding ───────────────────────────────────────────────────────────────────────

local function dropHold()
    if not holdTarget then return end
    holdTarget:UnregisterEvent("PLAYER_REGEN_ENABLED")
    holdTarget = nil
end

--- Where the skin picker opens: centered across, its CENTER HEIGHT_SHARE of the way up UIParent, the
--- bare CENTER when UIParent's height cannot be read.
local function place(f)
    local h = UIParent and type(UIParent.GetHeight) == "function" and UIParent:GetHeight() or 0
    f:ClearAllPoints()
    if type(h) == "number" and h > 0 then
        f:SetPoint("CENTER", UIParent, "BOTTOM", 0, h * HEIGHT_SHARE)
    else
        f:SetPoint("CENTER")
    end
end

--- Show the window, fresh when it was down: Simple selected, nothing picked, placed, the containers
--- unlocked and test mode on. The skin picker goes down first, unmarked; it comes back after the close.
local function show()
    local f = Picker.frame or build()
    local fresh = not f:IsShown()
    if fresh then
        state.sel, state.picked, state.open = "simple", false, true
        place(f)
        openUnlocked()
    end
    -- A profile with nothing of its own previews the selection at once (the header).
    if fresh and Presets.OwnContainerCount() == 0 and not InCombatLockdown() then pick(state.sel) end
    if NS.HideSkinPicker then NS.HideSkinPicker() end
    f:Show()
    refresh()
    if f.Raise then f:Raise() end
    -- A confirm shown before this window stays above it (frame-layering-§4).
    if KC and type(KC.RaiseStaticPopups) == "function" then KC.RaiseStaticPopups() end
    return f
end

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
    show()
    return true
end

--- `/rm preset`: the window on demand, whatever the profile has seen. Refused in combat and while the
--- addon stands down. Answers the window, or nil.
function NS.ShowPresetPicker()
    if InCombatLockdown() then
        return sayGray(L["cannot open the preset picker during combat; a preview rebuilds your range displays"])
    end
    if NS.IsStoodDown() then return print(L["Range Master disabled \226\128\148 /rm enable turns it back on"]) end
    return show()
end

--- Take the picker down unanswered, its preview restored, and drop a held showing and an open
--- confirm: the stand-down, every profile event and AceDB's shutdowns. Offers no skin picker.
--- `replaced` true when the active profile was just replaced whole (a reset or a copy): the preview
--- is dropped, not restored, and no lock is written.
function NS.HidePresetPicker(replaced)
    dropHold()
    dropConfirm()
    if replaced then Presets.DropPreview() end
    local f = Picker.frame
    if not (f and f:IsShown()) then return end
    if Presets.EndPreview(false) then NS.SelectContainer(nil) end
    settle(state.lockedAtOpen, replaced)
    state.picked, state.open = false, false
    closing = true
    f:Hide()
    closing = false
end

--- Combat started (core/RangeMaster.lua's edge): a preview up is restored, the window repainted.
function NS.PresetPickerCombat()
    local f = Picker.frame
    if not (f and f:IsShown()) then return end
    if Presets.EndPreview(false) then
        state.picked = false
        NS.SelectContainer(nil)
    end
    refresh()
end

--- True while the window is up or a showing is held: the skin picker waits behind it.
function NS.PresetPickerHolding()
    local f = Picker.frame
    return holdTarget ~= nil or (f ~= nil and f:IsShown() == true)
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

-- Suite seams (tests/test_settings_presets.lua): the hold, and the window's controls as its buttons
-- and its dropdown call them.
function NS.__presetPickerHeld() return holdTarget ~= nil end
Picker.__controls = { pick = function(k) pick(k) end, apply = function() apply() end,
    dismiss = function() dismiss() end, settings = function() openSettings() end,
    toggleLock = function() toggleLock() end, toggleTest = function() toggleTest() end }
