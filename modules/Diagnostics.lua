local _, NS = ...
-- modules/Diagnostics.lua — the addon's sections of `/rm diagnostics` (debug-logging-§14).
--
-- The library writes everything around the sections: both markers, its half of the identity header
-- (client build, locale, debug flag, combat reads, the running LibKa0s minors, the [Init] summary), a
-- pcall per section, the cap and the truncated line. This file writes SECTIONS ONLY; a hand-rolled
-- buffer, pcall wrapper, marker or Add loop would be anti-pattern #90.
--
-- Read state, never act: no hold, no event, no timer, no stand-up, and safe in combat. `out:add` runs
-- every argument through safeToString, so raw values go in. docs/debug.md lists every section.
NS.Diagnostics = NS.Diagnostics or {}
local D = NS.Diagnostics

-- The rows the settings section prints whatever their value.
local ALWAYS = { "enabled", "visibility", "alpha", "scale", "locked", "global.minimap.shown" }

-- The libraries the addon resolves through LibStub, named once for the missing-library line.
local LIBRARIES = {
    "AceAddon-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0", "AceDB-3.0", "AceGUI-3.0",
    "AceConfig-3.0", "AceDBOptions-3.0", "LibDataBroker-1.1", "LibDBIcon-1.0",
    "LibSharedMedia-3.0", "LibRangeCheck-3.0",
    "LibKa0s-Core-1.0", "LibKa0s-Env-1.0", "LibKa0s-Compat-1.0", "LibKa0s-Lifecycle-1.0",
    "LibKa0s-Bus-1.0", "LibKa0s-Schema-1.0", "LibKa0s-Media-1.0", "LibKa0s-Skin-1.0",
    "LibKa0s-DebugLog-1.0", "LibKa0s-Slash-1.0", "LibKa0s-Launcher-1.0", "LibKa0s-Options-1.0",
    "LibKa0s-Perf-1.0",
}

local function stoodDown() return NS.IsStoodDown and NS.IsStoodDown() or false end

local function holdsText()
    local holds = NS.lifecycle and NS.lifecycle:Holds() or {}
    if #holds == 0 then return "none" end
    return table.concat(holds, ", ")
end

local function stateSection(out)
    local db = NS.db
    local global = db and db.global
    out:add(nil, "schema: stored=%s code=%s", global and global.schemaVersion, NS.SCHEMA_VERSION)
    local ok, profile = pcall(function() return db:GetCurrentProfile() end)
    out:add(nil, "profile: %s", ok and profile or "unreadable")
    out:add(nil, "client: %s", NS.Compat.ClientKey() or "unknown")
    out:add(nil, "enabled (stored)=%s stood down=%s", NS.GetSetting("enabled") ~= false, stoodDown())
    out:add(nil, "test mode=%s sim mode=%s", NS.IsTestMode(), NS.IsSimMode())
end

local function lifecycleSection(out)
    out:add("Life", "holds: %s", holdsText())
    local P = NS.Perf
    out:add("Life", "perf: capturing=%s", P and P.on)
    out:add("Life", "bus: %s", stoodDown() and "stood down (every tracked subscription released)" or "live")
end

local function settingsSection(out)
    out:nonDefaults(NS.Schema,
        function(row) return NS.GetSetting(row.path) end,
        nil,
        function(row, v) return NS.FormatSchemaValue(row, v) end,
        { always = ALWAYS })
end

local function aceEventNames()
    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
    local registry = AceEvent and AceEvent.events and AceEvent.events.events
    local names = {}
    if type(registry) ~= "table" then return names end
    for name, owners in pairs(registry) do
        if type(owners) == "table" and owners[NS.addon] ~= nil then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

local function eventsSection(out)
    if stoodDown() then
        return out:add("Events", "stood down: every registration released (holds: %s)", holdsText())
    end
    out:joined("Events", "AceEvent registered:", aceEventNames())
end

local function rejectedSection(out)
    out:list("Events", "rejected events:", NS.State and NS.State.rejectedEvents or {})
end

local function uiSection(out)
    local panel = _G.SettingsPanel
    local open = type(panel) == "table" and type(panel.IsShown) == "function" and panel:IsShown()
    out:add("UI", "settings panel open=%s", open and true or false)
    local L = NS.Launcher
    out:add("UI", "launcher: registered=%s shown=%s", L and L:IsRegistered(), L and L:IsShown())
    out:joined("UI", "libraries missing:", D.MissingLibraries())
end

--- The majors from LIBRARIES that did not load, in that order. Read by the [Init] summary too.
function D.MissingLibraries()
    local missing = {}
    for _, major in ipairs(LIBRARIES) do
        if not (LibStub and LibStub(major, true)) then missing[#missing + 1] = major end
    end
    return missing
end

local SECTIONS = {
    { "state",     stateSection },
    { "lifecycle", lifecycleSection },
    { "settings",  settingsSection },
    { "events",    eventsSection },
    { "rejected",  rejectedSection },
    { "ui",        uiSection },
}

--- The sections, as `{ name, fn }` pairs, a fresh list per run.
function D.Sections()
    local out = {}
    for i, entry in ipairs(SECTIONS) do out[i] = { entry[1], entry[2] } end
    return out
end
