local _, NS = ...
-- modules/FramePicker.lua — point at a frame on screen and click it, to put a container on it by
-- name (design spec 5.4, the custom provider's click-to-pick).
--
--   NS.FramePicker.Start(onPick(frameName), onCancel?) -> started   refused in combat
--   NS.FramePicker.Stop()          end a pick with no callback (the stand-down)
--   NS.FramePicker.Cancel(why)     end a pick as a cancel (the combat edge)
--   NS.FramePicker.IsActive()
--   NS.FramePicker.NamedAncestor(frame) -> frame|nil, name|nil
--
-- While picking, an overlay tracks the topmost frame under the cursor (NS.Compat.GetMouseFocus),
-- walks up to its nearest NAMED ancestor (a container stores a frame's global name, so an unnamed
-- frame could not be found again after a /reload), outlines it and writes its name beside the cursor.
-- Left click takes it, right click or Escape cancels. The overlay never takes the mouse (it would
-- be the frame under the cursor), clicks are read with IsMouseButtonDown, and the pick arms only once
-- both buttons are up, so the click that started it cannot pick the frame behind its button.
--
-- SAFE IN COMBAT BY NOT RUNNING IN IT. A pick is refused under combat lockdown (one gray line), and
-- combat starting ends one: core/RangeMaster.lua's combat edge cancels it, and the OnUpdate cancels
-- itself on the first frame it sees lockdown. The overlay toggles keyboard propagation, which the
-- client restricts in combat, so that call is made only out of combat. Every frame the walk meets is
-- asked IsForbidden first, under pcall, and the outline is placed on the picked frame under pcall.
-- It is modeled on AuraMaster's modules/FramePicker.lua.

NS.FramePicker = NS.FramePicker or {}
local FP = NS.FramePicker

local L = NS.L
local LAYERS = NS.Constants.LAYERS
local Style = NS.Style

local overlay, outline, edges, label
local onPick, onCancel
local armed = false

-- Never an anchor: the screen itself, and this addon's own frames.
local REJECT = { UIParent = true, WorldFrame = true }

local function isForbidden(f)
    if type(f.IsForbidden) ~= "function" then return false end
    local ok, v = pcall(f.IsForbidden, f)
    return not ok or v == true or NS.Compat.IsSecret(v)
end

local function nameOf(f)
    if type(f.GetName) ~= "function" then return nil end
    local ok, name = pcall(f.GetName, f)
    if not ok or type(name) ~= "string" or name == "" or NS.Compat.IsSecret(name) then return nil end
    return name
end

local function parentOf(f)
    if type(f.GetParent) ~= "function" then return nil end
    local ok, p = pcall(f.GetParent, f)
    return ok and type(p) == "table" and p or nil
end

function FP.NamedAncestor(f)
    local hops = 0
    while type(f) == "table" and hops < 32 do
        if isForbidden(f) or f == overlay or f == outline then return nil end
        local name = nameOf(f)
        if name and not REJECT[name] and not name:match("^RangeMaster") then return f, name end
        f = parentOf(f)
        hops = hops + 1
    end
    return nil
end

local function stop()
    armed = false
    if overlay then
        overlay:SetScript("OnUpdate", nil)
        overlay:Hide()
    end
end

function FP.Stop() stop() end

function FP.Cancel(why)
    if not FP.IsActive() then return end
    stop()
    NS.Debug("Anchor", "frame pick canceled (%s)", tostring(why))
    local cb = onCancel
    onPick, onCancel = nil, nil
    if cb then cb() end
end

local function picked(name)
    stop()
    NS.Debug("Anchor", "frame picked: %s", name)
    local cb = onPick
    onPick, onCancel = nil, nil
    if cb then cb(name) end
end

--- The outline and the name under the cursor.
local function track()
    local target, name = FP.NamedAncestor(NS.Compat.GetMouseFocus())
    outline:ClearAllPoints()
    if target and pcall(outline.SetAllPoints, outline, target) then outline:Show() else outline:Hide() end
    label:SetText(name and (name .. "\n" .. L["Left-click to pick, right-click to cancel"])
        or L["Point at a named frame. Right-click to cancel."])
    local x, y = GetCursorPosition()
    local s = tonumber(UIParent:GetEffectiveScale()) or 1
    if s <= 0 then s = 1 end
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (tonumber(x) or 0) / s + 16, (tonumber(y) or 0) / s + 16)
    return name
end

local function onUpdate()
    if InCombatLockdown() then return FP.Cancel("combat") end
    local left, right = IsMouseButtonDown("LeftButton"), IsMouseButtonDown("RightButton")
    if not armed then
        if not (left or right) then armed = true end
        return
    end
    local name = track()
    if right then return FP.Cancel("right click") end
    if left and name then picked(name) end
end

local function onKeyDown(self, key)
    if key ~= "ESCAPE" or InCombatLockdown() then return end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    FP.Cancel("escape")
    C_Timer.After(0, function()
        if self.SetPropagateKeyboardInput and not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)
end

local function paint()
    if not outline then return end
    Style.PaintEdges(edges, NS.Skin.Color("text.accent"))
    label:SetTextColor(NS.Skin.Color("text.accent"))
end

local function build()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata(LAYERS.STRATA.PICKER)
    overlay:EnableMouse(false)
    overlay:EnableKeyboard(true)
    if overlay.SetPropagateKeyboardInput then overlay:SetPropagateKeyboardInput(true) end
    overlay:SetScript("OnKeyDown", onKeyDown)
    overlay:Hide()
    -- Plain strips hung on the corners, never a backdrop: the outline covers any frame, and a
    -- backdrop would read that frame's size, which can be secret.
    outline = CreateFrame("Frame", nil, overlay)
    edges = Style.NewEdges(outline, "OVERLAY")
    Style.LayEdges(outline, edges, 2)
    outline:Hide()
    label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetJustifyH("LEFT")
    paint()
end
NS.Skin.OnLooksChanged(paint)

function FP.Start(pick, cancel)
    if InCombatLockdown() then
        NS.Printf("|cff808080%s|r", L["Cannot pick a frame during combat."])
        NS.Debug("Anchor", "frame pick refused (in combat)")
        return false
    end
    if not overlay then build() end
    onPick, onCancel = pick, cancel
    armed = false
    overlay:Show()
    overlay:SetScript("OnUpdate", onUpdate)
    NS.Debug("Anchor", "frame pick started")
    return true
end

function FP.IsActive()
    return overlay ~= nil and overlay:GetScript("OnUpdate") ~= nil
end

-- Suite seam (tests/test_anchors_frame.lua).
function FP.__overlay() return overlay end
