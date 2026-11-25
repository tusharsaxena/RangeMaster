local addonName, NS = ...
-- settings/BandSetDialogs.lua — the Band sets page's three dialogs and the Undo after a copy or a
-- restore (RangeMaster#21, the band set manager spec's "Settings page" items 5 to 7 and "Undo").
--
--     New band set                        x     Copy bands from                     x
--     [Name                         ]           Into: Paladin            (or a dropdown of yours)
--     Start from                                [From v  your sets, then every preset ]
--     (•) A shipped preset   [Paladin v]        [x] Bands   [x] Sounds on enter
--     ( ) A copy of my set   [Mage    v]        [ ] Match rule and unknown label and color
--     ( ) Blank: one open-ended band            Paladin's 4 bands are replaced by X's 5. ...
--     [Create]               [Cancel]           [Copy]                 [Cancel]
--
--     Restore Paladin preset              x
--     Put 'Paladin' back to the Paladin preset. What changes:
--     Band 2 label: HOLY -> JUDGE   (up to 8 lines, then "and N more")
--     [x] Keep my sounds
--     [Restore]              [Cancel]
--
-- ONE WINDOW, THREE BODIES. A companion window of the settings panel (standalone-windows: owned by
-- the Band sets page, opened only from its buttons): MODAL strata, toplevel and clamped
-- (frame-layering-§1), a title and the close mark through LibKa0s-Widgets-1.0's HeaderButtons with
-- `companion = true` (no settings mark), painted through the skin (NS.ApplySkin, the facade's
-- Header). Its body is one AceGUI SimpleGroup with a Flow layout, parented to the window by hand as
-- the page's header is (settings/BandSets.lua), so its controls are the panel's own AceGUI widgets,
-- painted on Create. Opening another dialog, Escape (UISpecialFrames), the close mark, Cancel, the
-- Settings panel closing and a profile change (core/RangeMaster.lua's adoptProfile) take it down;
-- the body is released on every hide.
--
-- THE WRITES ARE modules/BandSets.lua's: New is Create (a preset key, or `{}` for blank: one
-- open-ended band) or Duplicate then Rename; Copy is CopyFrom; Restore is RestorePreset. Each answer
-- selects the set it wrote (NS.ShowBandSet, which also ends a preset's view).
--
-- UNDO (the spec's "Undo"): before a Copy or a Restore this file takes NS.BandSets.Snapshot(), and
-- the chat line names `/rm bands undo`, the addon's own Undo shape (`/rm preset undo` follows a
-- preset's Apply; no chat link exists in the addon or LibKa0s). One level, per profile, this
-- session. The Undo puts back only the set the copy or restore wrote: it takes the registry as it is
-- now, swaps in that set's copy from the snapshot and hands the result to RestoreSnapshot, so a set
-- made, edited or deleted since is not undone with it. It refuses when that set has been deleted.

local L = NS.L
local H = NS.Helpers
local print = NS.Print
local printf = NS.Printf

local KW = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
local KC = LibStub and LibStub("LibKa0s-Core-1.0", true)

local WINDOW = "RangeMasterBandSetDialog"
local WIDTH, PAD, TITLE_H = 440, 14, 36
local MAX_DIFF_LINES = 8
-- Each control's height, for the window's height where the body cannot be measured (the body's
-- own height is read first; AceGUI sets it when it lays the group out).
local EST = { label = 18, edit = 46, dropdown = 46, check = 26, buttons = 32 }

-- The dialog up: its frame, its body, which dialog it is and its controls (a test seam).
local D = { frame = nil, block = nil, kind = nil, w = {}, height = 0 }

local function page() return NS.BandSetsPage end

--- Call the skin facade's `member` when it has one (the degraded facade has no Header).
local function paint(member, ...)
    local fn = NS.Skin and NS.Skin[member]
    if type(fn) == "function" then return fn(...) end
end

-- ── the window ───────────────────────────────────────────────────────────────────────────────

--- Release the body, if one is drawn.
local function releaseBody()
    local block = D.block
    D.block, D.kind, D.title, D.w, D.height = nil, nil, nil, {}, 0
    if block and NS.AceGUI then NS.AceGUI:Release(block) end
end

--- Take the dialog down, unanswered.
local function hide()
    local f = D.frame
    if f and f:IsShown() then f:Hide() end
    releaseBody()
end
NS.HideBandSetDialog = hide

local function plainClose(parent, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    btn:SetScript("OnClick", function() onClick() end)
    return btn
end

--- The close mark, top right: HeaderButtons' strip for a companion window (no settings mark), or the
--- close alone without the library.
local function buildMarks(f)
    local function makeClose(parent, onClick)
        return NS.MakeCloseButton(parent, onClick) or plainClose(parent, onClick)
    end
    if KW and type(KW.HeaderButtons) == "function" then
        local hb = KW.HeaderButtons(f, { owner = addonName, frame = f, point = "TOPRIGHT", y = -8,
            companion = true, makeClose = makeClose, close = hide })
        f.close = hb.close
        return hb.right
    end
    f.close = makeClose(f, hide)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -8)
    return { { frame = f.close, x = 6 } }
end

local function buildFrame()
    local f = CreateFrame("Frame", WINDOW, UIParent, "BackdropTemplate")
    D.frame = f
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
    f:SetScript("OnHide", function() releaseBody() end)
    NS.ApplySkin(f)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if title.SetJustifyH then title:SetJustifyH("LEFT") end
    paint("Text", title, "heading")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -12)
    f.title = title
    paint("Header", f, { title = title, right = buildMarks(f) })
    local specials = UISpecialFrames
    if type(specials) == "table" then table.insert(specials, WINDOW) end
    return f
end

-- The Settings panel closing takes the dialog with it: it belongs to the Band sets page.
local hookedSettings = false
local function hookSettings()
    if hookedSettings then return end
    if type(SettingsPanel) == "table" and type(SettingsPanel.HookScript) == "function" then
        SettingsPanel:HookScript("OnHide", function() hide() end)
        hookedSettings = true
    end
end

--- Size the window to its body: the body's laid-out height, or the controls' estimate.
local function layout()
    local block, f = D.block, D.frame
    if not (block and f) then return end
    block:DoLayout()
    local h = block.frame and block.frame.GetHeight and block.frame:GetHeight()
    if type(h) ~= "number" or h <= 0 then h = D.height end
    f:SetHeight(TITLE_H + h + PAD)
end

--- Open dialog `kind` titled `title`, its body filled by `fill(block, w)`. Answers D, or nil when
--- AceGUI is missing.
local function open(kind, title, fill)
    if not NS.AceGUI then return nil end
    local f = D.frame or buildFrame()
    releaseBody()
    local block = NS.AceGUI:Create("SimpleGroup")
    if not (block and block.frame) then return nil end
    block:SetLayout("Flow")
    block.frame:SetParent(f)
    block.frame:ClearAllPoints()
    block.frame:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TITLE_H)
    block.frame:Show()
    block:SetWidth(WIDTH - 2 * PAD)
    D.block, D.kind, D.title = block, kind, title
    f.title:SetText(title)
    fill(block, D.w)
    if not f:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    f:Show()
    layout()
    if f.Raise then f:Raise() end
    if KC and type(KC.RaiseStaticPopups) == "function" then KC.RaiseStaticPopups() end
    hookSettings()
    NS.Debug("BandSets", "dialog %s shown", kind)
    return D
end

-- ── the controls ─────────────────────────────────────────────────────────────────────────────

local function add(block, w, rel, est)
    if rel then w:SetRelativeWidth(rel) else w:SetFullWidth(true) end
    block:AddChild(w)
    D.height = D.height + (est or 0)
    return w
end

local function label(block, text, font, rel)
    local w = NS.AceGUI:Create("Label")
    w:SetText(text)
    if font then H.LabelFont(w, font) end
    local lines = math.max(1, math.ceil(#tostring(text) / 70))
    return add(block, w, rel, EST.label * lines)
end

local function editBox(block, text, value, tip)
    local w = NS.AceGUI:Create("EditBox")
    w:SetLabel(text)
    w:SetText(value)
    w:SetMaxLetters(40)
    if w.DisableButton then w:DisableButton(true) end
    H.AttachTooltip(w, text, tip)
    return add(block, w, nil, EST.edit)
end

--- A dropdown of `list`/`order` on `value`; its group rows (`headers`) are disabled, and choosing one
--- anyway puts the value back. `onPick(v)` hears every real choice.
local function dropdown(block, text, entries, value, onPick, rel, tip)
    local w = NS.AceGUI:Create("Dropdown")
    w:SetLabel(text)
    local function fill(e)
        w:SetList(e.list, e.order)
        for _, key in ipairs(e.headers or {}) do
            if w.SetItemDisabled then w:SetItemDisabled(key, true) end
        end
    end
    fill(entries)
    w.rmRefill = fill
    w:SetValue(value)
    w.rmValue = value
    w:SetCallback("OnValueChanged", function(_, _, v)
        local headerKey = page().HeaderKey
        if type(v) == "string" and v:find(headerKey, 1, true) == 1 then return w:SetValue(w.rmValue) end
        w.rmValue = v
        onPick(v)
    end)
    if tip then H.AttachTooltip(w, text ~= "" and text or nil, tip) end
    return add(block, w, rel, rel and 0 or EST.dropdown)
end

local function checkBox(block, text, value, onToggle, rel, tip, est)
    local w = NS.AceGUI:Create("CheckBox")
    w:SetLabel(text)
    w:SetValue(value and true or false)
    w:SetCallback("OnValueChanged", function(_, _, v) onToggle(v and true or false) end)
    if tip then H.AttachTooltip(w, text, tip) end
    return add(block, w, rel, est == nil and EST.check or est)
end

--- The answer row: the dialog's act and Cancel, side by side.
local function buttons(block, w, text, onClick)
    local act = NS.AceGUI:Create("Button")
    act:SetText(text)
    act:SetCallback("OnClick", function()
        local ok, err = pcall(onClick)
        if not ok then print(tostring(err)) end
    end)
    add(block, act, 0.5, EST.buttons)
    local cancel = NS.AceGUI:Create("Button")
    cancel:SetText(L["Cancel"])
    cancel:SetCallback("OnClick", function() hide() end)
    add(block, cancel, 0.5, 0)
    w.act, w.cancel = act, cancel
end

-- ── the entries the dropdowns list ───────────────────────────────────────────────────────────

local function presetValue(key) return page().ViewPrefix .. key end

--- The preset key of a "preset:<key>" value, or nil.
local function presetKeyOf(v)
    return type(v) == "string" and v:match("^" .. page().ViewPrefix .. "(.+)$") or nil
end

--- Every shipped preset, under its two group rows.
local function presetEntries()
    local e = { list = {}, order = {}, headers = {} }
    page().AddPresets(e.list, e.order, e.headers)
    return e
end

--- The player's sets but `except`, with no group row.
local function ownEntries(except)
    local e = { list = {}, order = {}, headers = {} }
    page().AddOwnSets(e.list, e.order, except)
    return e
end

--- The player's sets but `except` under "Your band sets" (none when there is no other), then every
--- preset: Copy bands from's sources.
local function sourceEntries(except)
    local e = { list = {}, order = {}, headers = {} }
    local P = page()
    local key = P.HeaderKey .. "mine"
    P.AddHeader(e.list, e.order, e.headers, "mine", L["Your band sets"])
    if P.AddOwnSets(e.list, e.order, except) == 0 then
        table.remove(e.order, 1)
        e.list[key], e.headers = nil, {}
    end
    P.AddPresets(e.list, e.order, e.headers)
    return e
end

--- The first choosable value of `entries` (not a group row), or nil.
local function firstValue(entries)
    local headerKey = page().HeaderKey
    for _, v in ipairs(entries.order) do
        if not (type(v) == "string" and v:find(headerKey, 1, true) == 1) then return v end
    end
end

--- Whether `v` is one of `entries`' choosable values.
local function listed(entries, v)
    for _, o in ipairs(entries.order) do
        if o == v then return v ~= nil and entries.list[v] ~= nil end
    end
    return false
end

-- ── Undo ─────────────────────────────────────────────────────────────────────────────────────

local undo   -- { snap, id, profile }: the one level, taken before the last Copy or Restore

local function remember(snap, id)
    undo = snap and { snap = snap, id = id, profile = NS.db and NS.db.profile } or nil
end

--- Whether `/rm bands undo` has anything to put back on this profile.
function NS.CanUndoBandSets()
    return undo ~= nil and NS.db ~= nil and undo.profile == NS.db.profile
end

--- Drop the Undo slot: the profile it was taken on is no longer the one in use.
function NS.ForgetBandSetUndo()
    undo = nil
end

--- `/rm bands undo`: put the set the last Copy bands from or Restore preset wrote back as it was.
--- Answers whether anything was undone.
function NS.UndoBandSets()
    if not NS.CanUndoBandSets() then
        undo = nil
        print(L["Nothing to undo: no Copy bands from or Restore preset on this profile this session."])
        return false
    end
    local u = undo
    local was, now = u.snap.bandSets and u.snap.bandSets[u.id], NS.BandSets.Snapshot()
    if not (was and now and now.bandSets and now.bandSets[u.id]) then
        undo = nil
        print(L["Nothing to undo: that band set has been deleted since."])
        return false
    end
    now.bandSets[u.id] = was
    if not NS.BandSets.RestoreSnapshot(now) then return false end
    undo = nil
    NS.Debug("BandSets", "undo: set %s put back", tostring(u.id))
    NS.ShowBandSet(u.id)
    printf(L["Undone: '%s' is back as it was."], NS.BandSets.Get(u.id).name)
    return true
end

-- ── New… ─────────────────────────────────────────────────────────────────────────────────────

--- The preset New starts on: the one asked for, else your class's, else the first listed.
local function startPreset(asked)
    local e = presetEntries()
    if asked and listed(e, presetValue(asked)) then return presetValue(asked) end
    local mine = page().YourClassKey()
    if mine and listed(e, presetValue(mine)) then return presetValue(mine) end
    return firstValue(e)
end

--- The name New suggests for its start: the preset's, "<set> copy" or "New band set", made unique.
local function suggestedName(st)
    local base
    if st.mode == "preset" then
        base = page().PresetName(presetKeyOf(st.preset))
    elseif st.mode == "copy" then
        local set = NS.BandSets.Get(st.copy)
        base = set and L["%s copy"]:format(set.name)
    end
    return NS.BandSets.UniqueName(base or L["New band set"])
end

--- Make the set New describes, select it and close. Refuses aloud when nothing could be made.
local function createNew(st, w)
    local name, B = w.name:GetText(), NS.BandSets
    local id
    if st.mode == "preset" then
        id = B.Create(name, presetKeyOf(st.preset))
    elseif st.mode == "copy" then
        id = B.Duplicate(st.copy)
        if id then B.Rename(id, name) end
    else
        id = B.Create(name, {})
    end
    if not id then return print(L["That band set could not be made: its source is gone."]) end
    NS.Debug("BandSets", "new set %s (%s)", tostring(id), st.mode)
    hide()
    NS.ShowBandSet(id)
    printf(L["Made the band set '%s'."], B.Get(id).name)
end

--- New's three starts: one radio each, the chosen one's dropdown enabled.
local function newStarts(block, st, w)
    local function choose(mode)
        st.mode = mode
        for _, m in ipairs({ "preset", "copy", "blank" }) do w[m]:SetValue(m == mode) end
        w.presetList:SetDisabled(mode ~= "preset")
        w.copyList:SetDisabled(mode ~= "copy")
        if not st.touched then w.name:SetText(suggestedName(st)) end
    end
    local function radio(mode, text, rel, tip, est)
        local r = checkBox(block, text, st.mode == mode, function() choose(mode) end, rel, tip, est)
        r:SetType("radio")
        w[mode] = r
    end
    radio("preset", L["A shipped preset"], 0.45, L["A copy of one of the presets the addon ships."], EST.dropdown)
    w.presetList = dropdown(block, "", presetEntries(), st.preset, function(v)
        st.preset = v
        choose("preset")
    end, 0.55)
    radio("copy", L["A copy of one of my sets"], 0.45, L["A copy of one of your band sets, sounds included."], EST.dropdown)
    w.copyList = dropdown(block, "", ownEntries(nil), st.copy, function(v)
        st.copy = v
        choose("copy")
    end, 0.55)
    radio("blank", L["Blank: one open-ended band"], nil, L["One band from 0 yards with no limit, to build on with Add band."])
    choose(st.mode)
end

--- The New dialog. `spec` = { preset = key?, name = string? }: Use this preset… prefills both.
function NS.ShowNewBandSetDialog(spec)
    spec = type(spec) == "table" and spec or {}
    local _, selected = NS.SelectedBandSet()
    local st = { mode = "preset", preset = startPreset(spec.preset), copy = selected, touched = false }
    return open("new", L["New band set"], function(block, w)
        local start = spec.name and NS.BandSets.UniqueName(spec.name) or suggestedName(st)
        w.name = editBox(block, L["Name"], start, L["What the new band set is called. A name another set has gets a number."])
        w.name:SetCallback("OnTextChanged", function() st.touched = true end)
        label(block, L["Start from"], "GameFontNormal")
        newStarts(block, st, w)
        buttons(block, w, L["Create"], function() createNew(st, w) end)
        if spec.name then w.name:SetText(start) end
        w.state = st
    end)
end

-- ── Copy bands from… ─────────────────────────────────────────────────────────────────────────

--- What CopyFrom takes for value `v`: a set id, or { preset = key }.
local function sourceOf(v)
    local key = presetKeyOf(v)
    if key then return { preset = key } end
    return v
end

--- The set value `v` names, as a set: one of yours, or a fresh copy of the preset.
local function sourceSet(v)
    local key = presetKeyOf(v)
    if key then return NS.BandSets.PresetSet(key) end
    return NS.BandSets.Get(v)
end

--- The value a `from` of the spec reads as: a set id, or "preset:<key>".
local function fromValue(from)
    if type(from) == "table" then return from.preset and presetValue(from.preset) or nil end
    return from
end

--- The one-line summary: what the copy replaces, and what stays.
local function copySummary(st)
    local into, src = NS.BandSets.Get(st.into), sourceSet(st.from)
    if not (into and src) then return "" end
    local n = #into.bands
    local key = n == 1 and L["%s's %d band is replaced by %s's %d."] or L["%s's %d bands are replaced by %s's %d."]
    local text = key:format(into.name, n, src.name, #src.bands)
    if st.general then text = text .. " " .. L["So are its match rule and unknown label and color."] end
    return text .. " " .. L["Its name and the containers using it stay."]
end

--- The source a target leaves: the one chosen while it is still listed, else the first listed.
local function keepSource(st)
    local e = sourceEntries(st.into)
    if not listed(e, st.from) then st.from = firstValue(e) end
    return e
end

--- Copy as Copy bands from describes, behind an Undo, select the set and close.
local function copyBands(st)
    local into, src = NS.BandSets.Get(st.into), sourceSet(st.from)
    if not (into and src) then return print(L["Nothing was copied: the band set or its source is gone."]) end
    local snap = NS.BandSets.Snapshot()
    if not NS.BandSets.CopyFrom(st.into, sourceOf(st.from), { sounds = st.sounds, general = st.general }) then
        return print(L["Nothing was copied: the band set or its source is gone."])
    end
    remember(snap, st.into)
    NS.Debug("BandSets", "copied %s into %s", tostring(st.from), tostring(st.into))
    hide()
    NS.ShowBandSet(st.into)
    printf(L["Copied the bands of '%s' into '%s'. /rm bands undo puts them back."], src.name, into.name)
end

local function copyInto(block, st, w, ask)
    if not ask then
        return label(block, L["Into: %s"]:format(NS.BandSets.Get(st.into).name), "GameFontHighlight")
    end
    w.into = dropdown(block, L["Into"], ownEntries(nil), st.into, function(v)
        st.into = v
        w.from.rmRefill(keepSource(st))
        w.from:SetValue(st.from)
        w.from.rmValue = st.from
        w.summary:SetText(copySummary(st))
        layout()
    end, nil, L["Which of your band sets takes the bands. Its name and the containers using it stay."])
end

--- Copy bands from…. `spec` = { into = id?, from = id | { preset = key }? }. With no `into` (Copy
--- into a set of mine…, from a preset viewed) the dialog asks which set, starting on the selected one.
function NS.ShowCopyBandsDialog(spec)
    spec = type(spec) == "table" and spec or {}
    local _, selected = NS.SelectedBandSet()
    local ask = not NS.BandSets.Get(spec.into)
    local st = { into = ask and selected or spec.into, from = fromValue(spec.from), sounds = true, general = false }
    if not NS.BandSets.Get(st.into) then return print(L["No band set exists yet."]) end
    local sources = keepSource(st)
    return open("copy", L["Copy bands from"], function(block, w)
        local function refresh()
            w.summary:SetText(copySummary(st))
            layout()
        end
        copyInto(block, st, w, ask)
        w.from = dropdown(block, L["From"], sources, st.from, function(v)
            st.from = v
            refresh()
        end, nil, L["Your other band sets, then every shipped preset."])
        w.bands = checkBox(block, L["Bands"], true, function() w.bands:SetValue(true) end, 0.5,
            L["Every band: its edge, rule, label and colors. Always copied."])
        w.bands:SetDisabled(true)
        w.sounds = checkBox(block, L["Sounds on enter"], st.sounds, function(v)
            st.sounds = v
            refresh()
        end, 0.5, L["Take the source's band sounds too (a shipped preset has none). Off: each band keeps the sound its place had."], 0)
        w.general = checkBox(block, L["Match rule and unknown label and color"], st.general, function(v)
            st.general = v
            refresh()
        end, nil, L["Take the source's Match band by and its unknown range label and color too."])
        w.summary = label(block, copySummary(st), "GameFontHighlightSmall")
        buttons(block, w, L["Copy"], function() copyBands(st) end)
        w.state = st
    end)
end

-- ── Restore <Preset> preset… ─────────────────────────────────────────────────────────────────

-- A set-wide difference's name in the Restore list (a band's is "Band <n> <word>").
local SET_WORDS = {
    matchBy = L["Match rule"], ["unknown.label"] = L["Unknown label"], ["unknown.color"] = L["Unknown color"],
    bands = L["Band count"],
}
local COLOR_FIELDS = { frameColor = true, textColor = true, indicatorColor = true, ["unknown.color"] = true }

--- A color as "#RRGGBB", in that color.
local function colorText(c)
    if type(c) ~= "table" then return L["(none)"] end
    local function byte(v) return math.floor(math.max(0, math.min(1, tonumber(v) or 1)) * 255 + 0.5) end
    return page().Colored(("#%02X%02X%02X"):format(byte(c.r), byte(c.g), byte(c.b)), c.r, c.g, c.b)
end

--- One side of a difference, as the Restore list shows it.
local function valueText(field, v)
    if field == "rule" then return page().RuleText(v) end
    if COLOR_FIELDS[field] then return colorText(v) end
    if field == "to" then return v == nil and L["no limit"] or L["%s yd"]:format(tostring(v)) end
    if field == "matchBy" then return page().Match[v] or tostring(v) end
    if v == nil or v == "" then return L["(none)"] end
    return tostring(v)
end

--- A Diff entry as one line: "Band 2 label: HOLY -> JUDGE".
local function diffLine(e)
    local what = e.band and L["Band %d %s"]:format(e.band, page().DiffWords[e.field] or tostring(e.field))
        or SET_WORDS[e.field] or tostring(e.field)
    return L["%s: %s -> %s"]:format(what, valueText(e.field, e.mine), valueText(e.field, e.preset))
end
NS.__bandSetDiffLine = diffLine

--- Restore as the dialog describes, behind an Undo, select the set and close.
local function restore(id, st, name)
    local snap = NS.BandSets.Snapshot()
    if not NS.BandSets.RestorePreset(id, st.keep) then
        return print(L["Nothing was restored: the band set or its preset is gone."])
    end
    remember(snap, id)
    NS.Debug("BandSets", "restored set %s (keep sounds %s)", tostring(id), tostring(st.keep))
    hide()
    NS.ShowBandSet(id)
    printf(L["Restored '%s' to the %s preset. /rm bands undo puts it back."], NS.BandSets.Get(id).name, name)
end

--- The Restore dialog for set `id`: what differs from its preset (up to eight lines, then how many
--- more), Keep my sounds, then Restore. Refuses aloud a set with no preset on this client, and one
--- that already matches it.
function NS.ShowRestoreBandSetDialog(id)
    local set, diff = NS.BandSets.Get(id), NS.BandSets.Diff(id)
    if not diff then
        return print(L["This band set was not made from a shipped preset on this client: there is nothing to restore."])
    end
    local name = page().PresetName(set.origin)
    if #diff == 0 then return printf(L["'%s' already matches the %s preset."], set.name, name) end
    local st = { keep = true }
    return open("restore", L["Restore %s preset"]:format(name), function(block, w)
        label(block, L["Put '%s' back to the %s preset. What changes:"]:format(set.name, name), "GameFontHighlight")
        w.lines = {}
        for i = 1, math.min(MAX_DIFF_LINES, #diff) do
            w.lines[i] = label(block, diffLine(diff[i]), "GameFontHighlightSmall")
        end
        if #diff > MAX_DIFF_LINES then
            w.more = label(block, L["and %d more"]:format(#diff - MAX_DIFF_LINES), "GameFontDisableSmall")
        end
        w.keep = checkBox(block, L["Keep my sounds"], st.keep, function(v) st.keep = v end, nil,
            L["Each band keeps the sound on enter its place has now. Off: the bands come back with no sounds, as the preset ships."])
        buttons(block, w, L["Restore"], function() restore(id, st, name) end)
        w.state = st
    end)
end

-- Suite seam (tests/test_settings_bandset_dialogs.lua): the dialog up, its kind and its controls.
NS.__bandSetDialog = function() return D end
